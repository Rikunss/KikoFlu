package app.simple.felicity.dialogs.app

import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import androidx.core.view.isVisible
import androidx.fragment.app.FragmentManager
import app.simple.felicity.R
import app.simple.felicity.databinding.DialogUsbAudioDiagnosticBinding
import app.simple.felicity.extensions.dialogs.ScopedBottomSheetFragment
import app.simple.felicity.theme.managers.ThemeManager

/**
 * Bottom-sheet dialog that diagnoses whether the connected USB DAC supports
 * bit-perfect audio output via the Android 14+ [AudioMixerAttributes] API.
 *
 * Queries [AudioManager.getSupportedMixerAttributes] for each USB output device
 * and reports whether [AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT] is available,
 * along with all supported formats, sample rates, and channel masks.
 */
class UsbAudioDiagnosticDialog : ScopedBottomSheetFragment() {

    private var binding: DialogUsbAudioDiagnosticBinding? = null

    companion object {
        private const val TAG = "UsbAudioDiagnosticDialog"

        fun newInstance(): UsbAudioDiagnosticDialog = UsbAudioDiagnosticDialog()

        fun FragmentManager.showUsbAudioDiagnostic() {
            if (findFragmentByTag(TAG) == null) {
                newInstance().show(this, TAG)
            }
        }
    }

    override fun onCreateView(
            inflater: LayoutInflater,
            container: ViewGroup?,
            savedInstanceState: Bundle?
    ): View {
        binding = DialogUsbAudioDiagnosticBinding.inflate(inflater, container, false)
        return binding!!.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        runDiagnostic()
    }

    private fun runDiagnostic() {
        val b = binding ?: return

        if (Build.VERSION.SDK_INT < 34) {
            showMessage(getString(R.string.requires_android_14))
            return
        }

        val audioManager = requireContext().getSystemService(AudioManager::class.java)
        val usbDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }

        if (usbDevices.isEmpty()) {
            showMessage(getString(R.string.no_usb_device))
            return
        }

        b.deviceSection.isVisible = true
        b.message.isVisible = false

        // Use the first USB device (primary DAC)
        val device = usbDevices.first()
        bindDeviceInfo(device, audioManager)
    }

    @RequiresApi(34)
    private fun bindDeviceInfo(device: AudioDeviceInfo, audioManager: AudioManager) {
        val b = binding ?: return

        val deviceName = device.productName?.toString()?.ifBlank { "USB Audio Device" }
                ?: "USB Audio Device"

        b.valueDeviceName.text = createSpannedString(
                getString(R.string.device_name), deviceName)

        b.valueAndroidVersion.text = createSpannedString(
                getString(R.string.android_version),
                getString(R.string.format_android_version,
                        Build.VERSION.RELEASE, Build.VERSION.SDK_INT))

        val mixerAttrs = audioManager.getSupportedMixerAttributes(device)
        val hasBitPerfect = mixerAttrs.any {
            it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT
        }

        val statusText = if (hasBitPerfect) {
            getString(R.string.supported)
        } else {
            getString(R.string.not_supported)
        }

        b.valueBitPerfectStatus.text = createSpannedString(
                getString(R.string.bit_perfect_status), statusText)

        // Build formats list
        val formatsText = buildString {
            if (mixerAttrs.isEmpty()) {
                append("No mixer attributes reported")
            } else {
                for ((index, attr) in mixerAttrs.withIndex()) {
                    if (index > 0) append("\n\n")
                    val behavior = if (attr.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT) {
                        "BIT_PERFECT"
                    } else {
                        "DEFAULT"
                    }
                    append("[$behavior]")

                    val format = attr.format
                    append("\n  ${encodingToString(format.encoding)}")
                    append("\n  ${format.sampleRate} Hz")
                    append("\n  ${channelMaskToString(format.channelMask)}")
                }
            }
        }

        b.valueFormatsList.text = formatsText
    }

    private fun showMessage(text: String) {
        val b = binding ?: return
        b.message.text = text
        b.message.isVisible = true
        b.deviceSection.isVisible = false
    }

    private fun encodingToString(encoding: Int): String {
        return when (encoding) {
            AudioFormat.ENCODING_PCM_8BIT -> "PCM 8-bit"
            AudioFormat.ENCODING_PCM_16BIT -> "PCM 16-bit"
            AudioFormat.ENCODING_PCM_24BIT_PACKED -> "PCM 24-bit"
            AudioFormat.ENCODING_PCM_32BIT -> "PCM 32-bit"
            AudioFormat.ENCODING_PCM_FLOAT -> "PCM Float 32-bit"
            AudioFormat.ENCODING_DSD -> "DSD"
            else -> "Encoding($encoding)"
        }
    }

    private fun channelMaskToString(mask: Int): String {
        return when (mask) {
            AudioFormat.CHANNEL_OUT_MONO -> "Mono"
            AudioFormat.CHANNEL_OUT_STEREO -> "Stereo"
            AudioFormat.CHANNEL_OUT_QUAD -> "Quad"
            AudioFormat.CHANNEL_OUT_5POINT1 -> "5.1"
            AudioFormat.CHANNEL_OUT_7POINT1_SURROUND -> "7.1"
            else -> "Channels(0x${mask.toString(16)})"
        }
    }

    private fun createSpannedString(label: String, value: String): Spanned {
        val separator = ": "
        val full = "$label$separator$value"
        val spannable = SpannableString(full)
        val valueStart = label.length + separator.length

        val primaryColor = ThemeManager.theme.textViewTheme.primaryTextColor
        val secondaryColor = ThemeManager.theme.textViewTheme.secondaryTextColor

        spannable.setSpan(
                ForegroundColorSpan(primaryColor),
                0, valueStart,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

        spannable.setSpan(
                ForegroundColorSpan(secondaryColor),
                valueStart, full.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

        return spannable
    }

    override fun onDestroyView() {
        super.onDestroyView()
        binding = null
    }
}
