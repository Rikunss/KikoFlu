#!/usr/bin/env python3
"""Fix merge conflict markers in HiResAudioPlugin.kt - keep 96f3b38 side."""
import re
import sys

filepath = 'android/app/src/main/kotlin/com/meteor/kikoeruflutter/HiResAudioPlugin.kt'

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Count conflicts
count = content.count('<<<<<<< HEAD')
print(f'Conflicts found: {count}')

# Fix 1: Large conflict in class body - HEAD has inline ExoPlayer code,
# 96f3b38 has delegation to ExoPlayerManager
# Replace "<<<<<<< HEAD ... ======= ... 96f3b38_content ... >>>>>>> hash"
# with 96f3b38 side only

# Use regex to find conflict blocks and keep only the 96f3b38 side
pattern = r'<<<<<<< HEAD\n(.*?)\n=======\n(.*?)\n>>>>>>> [^\n]+'

def keep_96f3b38(m):
    return m.group(2)  # Keep only 96f3b38 side

new_content = re.sub(pattern, keep_96f3b38, content, flags=re.DOTALL)

# Fix 2: Remove duplicate setUseLibusbSink in onMethodCall
# There are TWO 'setUseLibusbSink' handler blocks - remove the duplicated one
new_content = new_content.replace(
    '''            \"setUseLibusbSink\" -> {
                val enabled = call.argument<Boolean>(\"enabled\") ?: false
                setUseLibusbSink(enabled)
                result.success(true)
            }
            \"setUseAaudioSink\" -> {
                val enabled = call.argument<Boolean>(\"enabled\") ?: false
                playerManager.setUseAaudioSink(enabled)
                result.success(true)
            }
            \"setUseLibusbSink\" -> {
                val enabled = call.argument<Boolean>(\"enabled\") ?: false
                if (playerManager.useDecentSink == enabled) {
                    result.success(true)
                    return
                }
                playerManager.useDecentSink = enabled
                playerManager.releasePlayer()
                android.util.Log.i(\"HiResAudio\", \"Decent-player UsbAudioSink ${if (enabled) \"enabled\" else \"disabled\"}\")
                result.success(true)
            }''',
    '''            \"setUseLibusbSink\" -> {
                val enabled = call.argument<Boolean>(\"enabled\") ?: false
                setUseLibusbSink(enabled)
                result.success(true)
            }
            \"setUseAaudioSink\" -> {
                val enabled = call.argument<Boolean>(\"enabled\") ?: false
                playerManager.setUseAaudioSink(enabled)
                result.success(true)
            }'''
)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(new_content)

remaining = new_content.count('<<<<<<< HEAD')
print(f'Remaining conflicts: {remaining}')
print('Done!')
