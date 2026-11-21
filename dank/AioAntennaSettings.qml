import qs.Modules.Plugins

PluginSettings {
    pluginId: "aioAntennaControl"

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Status refresh interval (seconds)"
        minimum: 2
        maximum: 30
        value: 5
    }

    StringSetting {
        settingKey: "pinctrlPath"
        label: "pinctrl executable"
        placeholder: "pinctrl"
    }

    StringSetting {
        settingKey: "ignoredWifiInterfaces"
        label: "Wifi interfaces to ignore (comma-separated)"
        placeholder: "e.g. wlan0 if it's a built-in radio, not the AC1200"
    }
}
