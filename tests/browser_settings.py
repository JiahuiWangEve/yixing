"""Production preference storage, not a runtime gameplay hook.

Install once per browser context so reload cannot undo a later UI toggle.
The ConfigFile text uses the exact public settings envelope written by Godot.
"""
import json
SETTINGS_KEY = 'yixing.settings.v1'
SETTINGS_ON = '[settings]\n\ndebug_mode=true\n'
async def install_debug_settings(page):
    await page.add_init_script('''if (!sessionStorage.getItem('qa-debug-settings-installed')) {
        localStorage.setItem(%s, %s);
        sessionStorage.setItem('qa-debug-settings-installed','1');
    }''' % (json.dumps(SETTINGS_KEY), json.dumps(SETTINGS_ON)))
