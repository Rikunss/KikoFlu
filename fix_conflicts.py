#!/usr/bin/env python3
"""Fix merge conflicts: keep 96f3b38 side, remove HEAD side."""
with open('lib/src/screens/settings/usb_dac_settings_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Strategy: Replace each conflict block
# "<<<<<<< HEAD ... HEAD content ... ======= ... 96f3b38 content ... >>>>>>> hash"
# with just the 96f3b38 content (between ======= and >>>>>>>)

import re

# Find all conflict blocks
pattern = r'<<<<<<< HEAD\n(.*?)\n=======\n(.*?)\n>>>>>>> [^\n]+'
def replace_conflict(m):
    return m.group(2)  # Keep only 96f3b38 side

new_content = re.sub(pattern, replace_conflict, content, flags=re.DOTALL)

# Find all conflict blocks that span across lines (where content is on the same line as markers)
pattern2 = r'<<<<<<< HEAD.*?\n=======\n(.*?)\n>>>>>>> [^\n]+'
new_content = re.sub(pattern2, replace_conflict, new_content, flags=re.DOTALL)

with open('lib/src/screens/settings/usb_dac_settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

remaining = new_content.count('<<<<<<< HEAD')
print(f'Remaining conflicts: {remaining}')
print('File fixed!')
