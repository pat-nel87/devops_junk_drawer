python __anonymous() {
    src_uri = d.getVar('SRC_URI')
    machine = d.getVar('MACHINE')
    bbwarn("🚨 MACHINE is: %s" % machine)
    bbwarn("🚨 SRC_URI is: %s" % src_uri)

    # Show patch list if any
    patches = [uri for uri in src_uri.split() if uri.startswith('file://')]
    bbnote("📦 Patches being applied:")
    for patch in patches:
        bbnote("  --> %s" % patch)

    # Optional: raise error if override didn't apply
    if "0001-G2V2-Provisioning-SD.patch" not in src_uri:
        bbwarn("⚠️  G2V2 provisioning patch not detected in SRC_URI!")
}

python __anonymous() {
    if d.getVar("PN") == "u-boot-fslc":
        bbwarn("🚧 We're inside u-boot-fslc!")
        bbwarn("📍 MACHINE = %s" % d.getVar("MACHINE"))
        bbwarn("📦 SRC_URI = %s" % d.getVar("SRC_URI"))
}
