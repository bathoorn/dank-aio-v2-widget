function sanitizeToken(value) {
  return String(value || "").replace(/[^A-Za-z0-9_.:-]/g, "")
}

function pinLine(output, pin) {
  var re = new RegExp("^\\s*" + pin + ":.*$", "m")
  var match = re.exec(output)
  return match ? match[0] : ""
}

function isLineOn(line) {
  return /\bhi\b/i.test(line) || /\bdh\b/i.test(line)
}

function parseWifiInterfaces(output) {
  var blocks = String(output || "").split(/^### /m).filter(function(b) { return b.trim() !== "" })
  return blocks.map(function(block) {
    var lines = block.split("\n")
    var header = lines[0].trim().split(/\s+/)
    var name = header[0] || ""
    var state = header[1] || ""
    var rest = lines.slice(1).join("\n")
    var connected = /Connected to/i.test(rest)
    var ssidMatch = /SSID:\s*(.+)/i.exec(rest)
    return {
      name: name,
      up: state === "up",
      connected: connected,
      ssid: connected && ssidMatch ? ssidMatch[1].trim() : ""
    }
  })
}

function wifiStatusScript(ignoredInterfaces) {
  var ignore = String(ignoredInterfaces || "").split(/[\s,]+/).map(sanitizeToken).filter(function(s) { return s !== "" })
  var lines = []
  lines.push("for i in /sys/class/net/*/wireless; do")
  lines.push("  [ -e \"$i\" ] || continue")
  lines.push("  IFACE=$(basename $(dirname \"$i\"))")
  ignore.forEach(function(name) {
    lines.push("  [ \"$IFACE\" = \"" + name + "\" ] && continue")
  })
  lines.push("  STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)")
  lines.push("  echo \"### $IFACE $STATE\"")
  lines.push("  iw dev \"$IFACE\" link 2>/dev/null")
  lines.push("done")
  return lines.join("\n")
}

function parseBluetoothAdapters(output) {
  var blocks = String(output || "").split(/\n(?=\d+: )/).filter(function(b) { return b.trim() !== "" })
  return blocks.map(function(block) {
    var header = /^(\d+):\s*(\S+):/.exec(block)
    if (!header) return null
    var soft = /Soft blocked:\s*(yes|no)/i.exec(block)
    var hard = /Hard blocked:\s*(yes|no)/i.exec(block)
    return {
      index: header[1],
      name: header[2],
      softBlocked: soft ? soft[1].toLowerCase() === "yes" : false,
      hardBlocked: hard ? hard[1].toLowerCase() === "yes" : false
    }
  }).filter(function(a) { return a !== null })
}
