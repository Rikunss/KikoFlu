package app.simple.felicity.ui.panels

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import app.simple.felicity.R
import app.simple.felicity.databinding.FragmentNetworkBrowserBinding
import app.simple.felicity.engine.services.FelicityPlayerService
import app.simple.felicity.extensions.fragments.ScopedFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.jcraft.jsch.ChannelSftp
import com.jcraft.jsch.JSch
import java.net.URL

/**
 * Simple network folder browser for SFTP and HTTP sources.
 * Navigates directories, plays audio files via ExoPlayer pipeline → USB.
 */
class NetworkBrowser : ScopedFragment() {

    private lateinit var binding: FragmentNetworkBrowserBinding
    private var adapter: NetworkBrowserAdapter? = null
    private var currentPath: String = ""
    private var baseUri: String = ""
    private var protocol: String = "sftp" // "sftp" or "http"

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        binding = FragmentNetworkBrowserBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        baseUri = arguments?.getString(ARG_BASE_URI) ?: ""
        currentPath = arguments?.getString(ARG_PATH) ?: ""
        protocol = arguments?.getString(ARG_PROTOCOL) ?: "sftp"

        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.title.text = if (currentPath.isEmpty()) {
            if (protocol == "sftp") "SFTP Browser" else "HTTP Browser"
        } else {
            currentPath.substringAfterLast("/").ifEmpty { currentPath }
        }

        loadDirectory()
    }

    private fun loadDirectory() {
        binding.progress.visibility = View.VISIBLE
        binding.recyclerView.visibility = View.GONE

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val entries = withContext(Dispatchers.IO) {
                    if (protocol == "sftp") loadSftpDirectory()
                    else loadHttpDirectory()
                }

                if (!isAdded) return@launch

                binding.progress.visibility = View.GONE
                binding.recyclerView.visibility = View.VISIBLE

                adapter = NetworkBrowserAdapter(entries) { entry ->
                    if (entry.isDirectory) {
                        // Navigate into folder
                        val newPath = if (currentPath.isEmpty()) entry.name
                        else "$currentPath/${entry.name}"
                        openFragment(newInstance(baseUri, newPath, protocol), TAG)
                    } else {
                        // Play file
                        playFile(entry)
                    }
                }
                binding.recyclerView.adapter = adapter

                if (entries.isEmpty() && isAdded) {
                    Toast.makeText(requireContext(), "Empty directory", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                if (!isAdded) return@launch
                binding.progress.visibility = View.GONE
                Log.e(TAG, "Failed to load directory", e)
                Toast.makeText(requireContext(), "Error: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    /**
     * Parse sftp://user:pass@host:port/path manually (java.net.URI rejects [] in paths).
     */
    private data class SftpUri(val user: String, val pass: String, val host: String, val port: Int, val path: String)

    private fun parseSftpUri(uri: String): SftpUri {
        // sftp://user:pass@host:port/path or sftp://user:pass@host/path
        val withoutScheme = uri.removePrefix("sftp://")
        val atIdx = withoutScheme.indexOf("@")
        val userInfo = withoutScheme.substring(0, atIdx)
        val hostAndPath = withoutScheme.substring(atIdx + 1)

        val user = userInfo.substringBefore(":")
        val pass = userInfo.substringAfter(":", "")

        val firstSlash = hostAndPath.indexOf("/")
        val hostPort = if (firstSlash >= 0) hostAndPath.substring(0, firstSlash) else hostAndPath
        val path = if (firstSlash >= 0) hostAndPath.substring(firstSlash) else "/"

        val host = hostPort.substringBefore(":")
        val port = hostPort.substringAfter(":", "22").toIntOrNull() ?: 22

        return SftpUri(user, pass, host, port, path)
    }

    private fun loadSftpDirectory(): List<NetworkEntry> {
        val fullUri = if (currentPath.isEmpty()) baseUri else "$baseUri/$currentPath"
        val decoded = java.net.URLDecoder.decode(fullUri, "UTF-8")
        Log.i(TAG, "SFTP listing: $decoded")

        val sftp = parseSftpUri(decoded)
        val host = sftp.host
        val port = sftp.port
        val user = sftp.user
        val pass = sftp.pass
        var path = sftp.path

        val jsch = JSch()
        val session = jsch.getSession(user, host, port)
        session.setPassword(pass)
        session.setConfig("StrictHostKeyChecking", "no")
        session.setConfig("PreferredAuthentications", "password,keyboard-interactive")
        session.connect(15000)

        val channel = session.openChannel("sftp") as ChannelSftp
        channel.connect(10000)

        try {
            // Try absolute path, then relative (chroot)
            var entries: java.util.Vector<ChannelSftp.LsEntry>? = null
            try {
                entries = channel.ls(path)
            } catch (_: Exception) {
                val relative = path.replace(Regex("^/home/[^/]+/"), "/")
                Log.w(TAG, "Absolute failed, trying: $relative")
                path = relative
                entries = channel.ls(path)
            }

            return (entries ?: emptyList<ChannelSftp.LsEntry>())
                .filter { e ->
                    val name = e.filename
                    name != "." && name != ".." && (e.attrs.isDir || isAudioFile(name))
                }
                .sortedWith(compareBy<ChannelSftp.LsEntry> { !it.attrs.isDir }.thenBy { it.filename.lowercase() })
                .map { e ->
                    val childPath = if (path.endsWith("/")) "$path${e.filename}" else "$path/${e.filename}"
                    // Build sftp:// URI for playback
                    val childUri = "sftp://$user:$pass@$host$childPath"
                    NetworkEntry(
                        name = e.filename,
                        isDirectory = e.attrs.isDir,
                        size = e.attrs.size,
                        uri = childUri
                    )
                }
        } finally {
            channel.disconnect()
            session.disconnect()
        }
    }

    private fun loadHttpDirectory(): List<NetworkEntry> {
        val fullUrl = if (currentPath.isEmpty()) baseUri else "$baseUri/$currentPath"
        Log.i(TAG, "HTTP listing: $fullUrl")

        val html = URL(fullUrl).readText()
        // Parse href links from directory listing (nginx, Apache, http-server, etc.)
        // Handles both href="/path" and href="\path" (Windows http-server uses backslashes)
        val linkRegex = Regex("""href="([^"]+)"[^>]*>([^<]+)<""")
        return linkRegex.findAll(html)
            .mapNotNull { match ->
                val href = match.groupValues[1].replace("\\", "/")
                // Decode HTML entities (&#47; = /, &#38; = &, etc.)
                val name = match.groupValues[2].trim()
                    .replace("&#47;", "/").replace("&#38;", "&")
                    .trimEnd('/')

                // Skip parent dir, sorting links, query params, non-content
                if (name.isEmpty() || name == ".." || name == "Parent Directory"
                    || href.startsWith("?") || name == "Music/") {
                    null
                } else {
                    val isDir = href.endsWith("/") || match.groupValues[0].contains("class=\"folder")
                    if (isDir || isAudioFile(name)) {
                        val encodedName = java.net.URLEncoder.encode(name, "UTF-8").replace("+", "%20")
                        val entryUrl = if (isDir) "$fullUrl/$encodedName" else "$fullUrl/$encodedName"
                        NetworkEntry(
                            name = name,
                            isDirectory = isDir,
                            size = 0,
                            uri = entryUrl
                        )
                    } else null
                }
            }
            .sortedWith(compareBy<NetworkEntry> { !it.isDirectory }.thenBy { it.name.lowercase() })
            .toList()
    }

    private fun playFile(entry: NetworkEntry) {
        val uri = if (protocol == "sftp") {
            java.net.URLDecoder.decode(entry.uri, "UTF-8")
        } else {
            entry.uri
        }

        Log.i(TAG, "Playing: $uri")

        // Build MediaItem with metadata so it shows in the player UI
        val title = entry.name.substringBeforeLast(".") // strip extension
        val item = androidx.media3.common.MediaItem.Builder()
            .setUri(uri)
            .setMediaId("network_${System.currentTimeMillis()}")
            .setMediaMetadata(
                androidx.media3.common.MediaMetadata.Builder()
                    .setTitle(title)
                    .setArtist(if (protocol == "sftp") "SFTP Stream" else "HTTP Stream")
                    .build()
            )
            .build()

        FelicityPlayerService.instance?.let { service ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                service.player.addMediaItem(item)
                val lastIndex = service.player.mediaItemCount - 1
                service.player.seekTo(lastIndex, 0)
                service.player.playWhenReady = true
            }
        }
        Toast.makeText(requireContext(), "Playing: ${entry.name}", Toast.LENGTH_SHORT).show()
    }

    private fun isAudioFile(name: String): Boolean {
        val ext = name.substringAfterLast(".", "").lowercase()
        return ext in setOf("flac", "mp3", "wav", "aac", "ogg", "opus", "m4a", "alac", "aiff", "wma")
    }

    companion object {
        const val TAG = "NetworkBrowser"
        private const val ARG_BASE_URI = "base_uri"
        private const val ARG_PATH = "path"
        private const val ARG_PROTOCOL = "protocol"

        fun newInstance(baseUri: String, path: String = "", protocol: String = "sftp"): NetworkBrowser {
            return NetworkBrowser().apply {
                arguments = Bundle().apply {
                    putString(ARG_BASE_URI, baseUri)
                    putString(ARG_PATH, path)
                    putString(ARG_PROTOCOL, protocol)
                }
            }
        }
    }
}

/** Simple data class for a file/folder entry in the network browser. */
data class NetworkEntry(
    val name: String,
    val isDirectory: Boolean,
    val size: Long,
    val uri: String
)
