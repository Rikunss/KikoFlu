package app.simple.felicity.ui.panels

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import app.simple.felicity.R

/**
 * Simple RecyclerView adapter for [NetworkBrowser].
 * Shows folders and audio files with icons.
 */
class NetworkBrowserAdapter(
    private val entries: List<NetworkEntry>,
    private val onClick: (NetworkEntry) -> Unit
) : RecyclerView.Adapter<NetworkBrowserAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val icon: ImageView = view.findViewById(R.id.network_item_icon)
        val name: TextView = view.findViewById(R.id.network_item_name)
        val info: TextView = view.findViewById(R.id.network_item_info)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.adapter_network_browser_item, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val entry = entries[position]

        holder.name.text = entry.name
        holder.icon.setImageResource(
            if (entry.isDirectory) R.drawable.ic_folder
            else R.drawable.ic_song
        )
        holder.info.text = if (entry.isDirectory) "" else formatSize(entry.size)

        holder.itemView.setOnClickListener { onClick(entry) }
    }

    override fun getItemCount() = entries.size

    private fun formatSize(bytes: Long): String {
        if (bytes <= 0) return ""
        val mb = bytes / (1024.0 * 1024.0)
        return String.format("%.1f MB", mb)
    }
}
