#!/usr/bin/env python3
"""Generate Whisker.xcodeproj/project.pbxproj"""

import os, textwrap

# ── UUID pool ────────────────────────────────────────────────────────────────
# 24-char hex strings, each unique within this file.
def u(n):
    # Prefix "A0" guarantees leading hex letters so the openstep plist
    # parser treats keys as identifiers, not all-numeric tokens.
    return f"A0{n:022X}"

P      = u(0x01)   # PBXProject
MGROUP = u(0x02)   # main group
PGROUP = u(0x03)   # Products group
TARGET = u(0x04)   # PBXNativeTarget
PCLIST = u(0x05)   # project XCConfigurationList
TCLIST = u(0x06)   # target  XCConfigurationList
PDEBUG = u(0x07)   # project debug config
PRELEASE=u(0x08)   # project release config
TDEBUG = u(0x09)   # target  debug config
TRELEASE=u(0x0A)   # target  release config
SRC_PH = u(0x0B)   # PBXSourcesBuildPhase
RES_PH = u(0x0C)   # PBXResourcesBuildPhase
FRM_PH = u(0x0D)   # PBXFrameworksBuildPhase
APP_PR = u(0x0E)   # app product file ref

# ── Keyboard Extension UUIDs ─────────────────────────────────────────────────
EXT_TARGET   = u(0xC0)   # extension PBXNativeTarget
EXT_TCLIST   = u(0xC1)   # extension XCConfigurationList
EXT_TDEBUG   = u(0xC2)   # extension debug config
EXT_TRELEASE = u(0xC3)   # extension release config
EXT_SRC_PH   = u(0xC4)   # extension PBXSourcesBuildPhase
EXT_FRM_PH   = u(0xC5)   # extension PBXFrameworksBuildPhase
EXT_RES_PH   = u(0xC6)   # extension PBXResourcesBuildPhase
EXT_APP_PR   = u(0xC7)   # extension product file ref
EXT_EMBED_PH = u(0xC8)   # PBXCopyFilesBuildPhase (embed extension)
EXT_DEP      = u(0xC9)   # PBXTargetDependency
EXT_PROXY    = u(0xCA)   # PBXContainerItemProxy
EXT_EMBED_BF = u(0xCB)   # embed build file
EXT_ENTITLE  = u(0xCC)   # extension entitlements file ref
APP_ENTITLE  = u(0xCD)   # main app entitlements file ref
EXT_PLIST    = u(0xCE)   # extension Info.plist file ref

# Source files: (uuid_ref, uuid_build, rel_path_from_Whisker_dir)
SOURCES = [
    (u(0x10), u(0x11), "DictationApp.swift"),
    (u(0x12), u(0x13), "RootView.swift"),
    (u(0x14), u(0x15), "AppState.swift"),
    (u(0x20), u(0x21), "Features/Recorder/RecorderView.swift"),
    (u(0x22), u(0x23), "Features/Recorder/AudioRecorder.swift"),
    (u(0x24), u(0x25), "Features/Recorder/RecordingSession.swift"),
    (u(0x26), u(0x27), "Features/Recorder/RecordingLimits.swift"),
    (u(0xEC), u(0xED), "Features/Recorder/RecordingSegmenter.swift"),
    (u(0x30), u(0x31), "Features/Transcription/TranscriptionEngine.swift"),
    (u(0x32), u(0x33), "Features/Transcription/TranscriptionViewModel.swift"),
    (u(0x40), u(0x41), "Features/Cleanup/CleanupMode.swift"),
    (u(0x42), u(0x43), "Features/Cleanup/CleanupPipeline.swift"),
    (u(0x44), u(0x45), "Features/Cleanup/RuleBasedCleaner.swift"),
    (u(0x48), u(0x49), "Features/Processing/DictationProcessor.swift"),
    (u(0x4C), u(0x4D), "Features/Remote/RemoteMacModels.swift"),
    (u(0x4E), u(0x4F), "Features/Remote/RemoteMacClient.swift"),
    (u(0x52), u(0x53), "Features/Remote/RemoteMacProcessor.swift"),
    (u(0x54), u(0x55), "Features/Remote/RemoteMacSettings.swift"),
    (u(0xE8), u(0xE9), "Features/Remote/SegmentBoundaryDetector.swift"),
    (u(0xEA), u(0xEB), "Features/Remote/StreamingDictationSession.swift"),
    (u(0x50), u(0x51), "Features/Clipboard/ClipboardService.swift"),
    (u(0x60), u(0x61), "Features/Settings/SettingsView.swift"),
    (u(0x62), u(0x63), "Features/Settings/ModelSettings.swift"),
    (u(0x64), u(0x65), "Features/Settings/PrivacySettings.swift"),
    (u(0x66), u(0x67), "Features/Settings/PermissionsOnboardingView.swift"),
    (u(0x70), u(0x71), "Shared/Models/Transcript.swift"),
    (u(0x72), u(0x73), "Shared/Models/DictationResult.swift"),
    (u(0x80), u(0x81), "Shared/Services/PermissionsService.swift"),
    (u(0x82), u(0x83), "Shared/Services/HistoryStore.swift"),
    (u(0x84), u(0x85), "Shared/Services/Logger.swift"),
    (u(0x86), u(0x87), "Shared/UI/WhiskerTheme.swift"),
    # Handoff (shared with extension)
    (u(0xD0), u(0xD1), "Shared/Handoff/HandoffResult.swift"),
    (u(0xD2), u(0xD3), "Shared/Handoff/HandoffService.swift"),
    (u(0xD4), u(0xD5), "Shared/Handoff/HandoffConstants.swift"),
    (u(0xD6), u(0xD7), "Shared/Handoff/HandoffCommand.swift"),
    (u(0xD8), u(0xD9), "Shared/Handoff/HandoffLaunchAction.swift"),
    (u(0xDA), u(0xDB), "Shared/Handoff/KeyboardSessionDefaults.swift"),
    (u(0xDC), u(0xDD), "Shared/Handoff/KeyboardTranscriptRecovery.swift"),
    (u(0xDE), u(0xDF), "Shared/Handoff/HandoffSignal.swift"),
    (u(0xF0), u(0xF1), "Shared/Handoff/KeyboardLiveTranscriptInserter.swift"),
]

# Resource files: (uuid_ref, uuid_build, rel_path_from_Whisker_dir)
RESOURCES = [
    (u(0x90), u(0x91), "Resources/Assets.xcassets"),
    (u(0x92), u(0x93), "Resources/PrivacyInfo.xcprivacy"),
]

# Extension source files: (uuid_ref, uuid_build, rel_path_from_WhiskerKeyboard_dir)
EXT_SOURCES = [
    (u(0xE0), u(0xE1), "KeyboardViewController.swift"),
]

# Shared files compiled into the extension target too (separate build file UUIDs)
EXT_SHARED_SOURCES = [
    (u(0xD0), u(0xE2), "Shared/Handoff/HandoffResult.swift"),
    (u(0xD2), u(0xE3), "Shared/Handoff/HandoffService.swift"),
    (u(0xD4), u(0xE4), "Shared/Handoff/HandoffConstants.swift"),
    (u(0xD6), u(0xE5), "Shared/Handoff/HandoffCommand.swift"),
    (u(0xDC), u(0xE6), "Shared/Handoff/KeyboardTranscriptRecovery.swift"),
    (u(0xDE), u(0xE7), "Shared/Handoff/HandoffSignal.swift"),
    (u(0xF0), u(0xF2), "Shared/Handoff/KeyboardLiveTranscriptInserter.swift"),
]

# ── Group helpers ────────────────────────────────────────────────────────────
# Build a tree so we can emit PBXGroup sections properly.
# Groups keyed by uuid
groups = {}   # uuid -> {name, parent, children: [uuid|file_ref]}
file_refs = {}  # uuid -> path

def ensure_group(path_parts, parent_uuid):
    """Return uuid for the group at path_parts under parent_uuid."""
    key = "/".join(path_parts)
    if key in _group_cache:
        return _group_cache[key]
    guid = u(0xA000 + len(_group_cache))
    name = path_parts[-1]
    groups[guid] = {"name": name, "parent": parent_uuid, "children": []}
    if parent_uuid in groups:
        groups[parent_uuid]["children"].append(guid)
    _group_cache[key] = guid
    return guid

_group_cache = {}

# Root "Whisker" source group
WHISKER_GROUP = u(0x100)
EXT_GROUP = u(0x101)
groups[WHISKER_GROUP] = {"name": "Whisker", "parent": MGROUP, "children": []}
groups[EXT_GROUP] = {"name": "WhiskerKeyboard", "parent": MGROUP, "children": []}
groups[MGROUP] = {"name": "Whisker", "parent": None,
                   "children": [WHISKER_GROUP, EXT_GROUP, PGROUP]}
groups[PGROUP] = {"name": "Products", "parent": MGROUP, "children": [APP_PR, EXT_APP_PR]}

def add_source(ref, path):
    parts = path.split("/")
    cur_parent = WHISKER_GROUP
    for i in range(len(parts) - 1):
        cur_parent = ensure_group(parts[:i+1], cur_parent)
    groups[cur_parent]["children"].append(ref)

for ref, bld, path in SOURCES:
    add_source(ref, path)
    file_refs[ref] = ("sourcecode.swift", path)

for ref, bld, path in RESOURCES:
    parts = path.split("/")
    # Resources are direct children of Whisker group if only 1 component
    if len(parts) == 1:
        groups[WHISKER_GROUP]["children"].append(ref)
    else:
        cur_parent = WHISKER_GROUP
        for i in range(len(parts) - 1):
            cur_parent = ensure_group(parts[:i+1], cur_parent)
        groups[cur_parent]["children"].append(ref)
    if path.endswith(".xcassets"):
        file_refs[ref] = ("folder.assetcatalog", path)
    else:
        file_refs[ref] = ("text.plist.xml", path)

# Extension sources
for ref, bld, path in EXT_SOURCES:
    groups[EXT_GROUP]["children"].append(ref)
    file_refs[ref] = ("sourcecode.swift", path)

# Extension support files (plist, entitlements) — add as file refs
file_refs[EXT_PLIST] = ("text.plist.xml", "Info.plist")
file_refs[EXT_ENTITLE] = ("text.plist.xml", "WhiskerKeyboard.entitlements")
file_refs[APP_ENTITLE] = ("text.plist.xml", "Whisker.entitlements")
groups[EXT_GROUP]["children"].append(EXT_PLIST)
groups[EXT_GROUP]["children"].append(EXT_ENTITLE)
groups[WHISKER_GROUP]["children"].append(APP_ENTITLE)

# ── Emit ─────────────────────────────────────────────────────────────────────
lines = []
A = lines.append

A("// !$*UTF8*$!")
A("{")
A("\tarchiveVersion = 1;")
A("\tclasses = {")
A("\t};")
A("\tobjectVersion = 77;")
A("\tobjects = {")
A("")

# PBXBuildFile
A("/* Begin PBXBuildFile section */")
for ref, bld, path in SOURCES:
    name = os.path.basename(path)
    A(f"\t\t{bld} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
for ref, bld, path in RESOURCES:
    name = os.path.basename(path)
    A(f"\t\t{bld} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
# Extension build files
for ref, bld, path in EXT_SOURCES:
    name = os.path.basename(path)
    A(f"\t\t{bld} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
for file_ref, bld, path in EXT_SHARED_SOURCES:
    name = os.path.basename(path)
    A(f"\t\t{bld} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {name} */; }};")
A(f"\t\t{EXT_EMBED_BF} /* WhiskerKeyboard.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {EXT_APP_PR} /* WhiskerKeyboard.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
A("/* End PBXBuildFile section */")
A("")

# PBXFileReference
A("/* Begin PBXFileReference section */")
A(f"\t\t{APP_PR} /* Whisker.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Whisker.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
A(f"\t\t{EXT_APP_PR} /* WhiskerKeyboard.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = WhiskerKeyboard.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
for ref, (ftype, path) in file_refs.items():
    name = os.path.basename(path)
    A(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {name}; sourceTree = \"<group>\"; }};")
A("/* End PBXFileReference section */")
A("")

# PBXFrameworksBuildPhase
A("/* Begin PBXFrameworksBuildPhase section */")
A(f"\t\t{FRM_PH} /* Frameworks */ = {{")
A(f"\t\t\tisa = PBXFrameworksBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tfiles = (")
A(f"\t\t\t);")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")
A(f"\t\t{EXT_FRM_PH} /* Frameworks */ = {{")
A(f"\t\t\tisa = PBXFrameworksBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tfiles = (")
A(f"\t\t\t);")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")
A("/* End PBXFrameworksBuildPhase section */")
A("")

# PBXCopyFilesBuildPhase (embed extension in main app)
A("/* Begin PBXCopyFilesBuildPhase section */")
A(f"\t\t{EXT_EMBED_PH} /* Embed App Extensions */ = {{")
A(f"\t\t\tisa = PBXCopyFilesBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tdstPath = \"\";")
A(f"\t\t\tdstSubfolderSpec = 13;")
A(f"\t\t\tfiles = (")
A(f"\t\t\t\t{EXT_EMBED_BF} /* WhiskerKeyboard.appex in Embed App Extensions */,")
A(f"\t\t\t);")
A(f"\t\t\tname = \"Embed App Extensions\";")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")
A("/* End PBXCopyFilesBuildPhase section */")
A("")

# PBXContainerItemProxy
A("/* Begin PBXContainerItemProxy section */")
A(f"\t\t{EXT_PROXY} /* PBXContainerItemProxy */ = {{")
A(f"\t\t\tisa = PBXContainerItemProxy;")
A(f"\t\t\tcontainerPortal = {P} /* Project object */;")
A(f"\t\t\tproxyType = 1;")
A(f"\t\t\tremoteGlobalIDString = {EXT_TARGET};")
A(f"\t\t\tremoteInfo = WhiskerKeyboard;")
A(f"\t\t}};")
A("/* End PBXContainerItemProxy section */")
A("")

# PBXTargetDependency
A("/* Begin PBXTargetDependency section */")
A(f"\t\t{EXT_DEP} /* PBXTargetDependency */ = {{")
A(f"\t\t\tisa = PBXTargetDependency;")
A(f"\t\t\ttarget = {EXT_TARGET} /* WhiskerKeyboard */;")
A(f"\t\t\ttargetProxy = {EXT_PROXY} /* PBXContainerItemProxy */;")
A(f"\t\t}};")
A("/* End PBXTargetDependency section */")
A("")

# PBXGroup
A("/* Begin PBXGroup section */")

def emit_group(guid):
    g = groups[guid]
    name = g["name"]
    children_str = "\n".join(
        f"\t\t\t\t{c}," for c in g["children"]
    )
    if guid == MGROUP:
        A(f"\t\t{guid} = {{")
        A(f"\t\t\tisa = PBXGroup;")
        A(f"\t\t\tchildren = (")
        A(children_str)
        A(f"\t\t\t);")
        A(f"\t\t\tsourceTree = \"<group>\";")
        A(f"\t\t}};")
    elif guid == PGROUP:
        A(f"\t\t{guid} /* {name} */ = {{")
        A(f"\t\t\tisa = PBXGroup;")
        A(f"\t\t\tchildren = (")
        A(children_str)
        A(f"\t\t\t);")
        A(f"\t\t\tname = {name};")
        A(f"\t\t\tsourceTree = \"<group>\";")
        A(f"\t\t}};")
    else:
        A(f"\t\t{guid} /* {name} */ = {{")
        A(f"\t\t\tisa = PBXGroup;")
        A(f"\t\t\tchildren = (")
        A(children_str)
        A(f"\t\t\t);")
        A(f"\t\t\tname = {name};")
        A(f"\t\t\tpath = {name};")
        A(f"\t\t\tsourceTree = \"<group>\";")
        A(f"\t\t}};")

# Emit all groups
all_group_uuids = [MGROUP] + [g for g in groups if g != MGROUP]
for g in all_group_uuids:
    emit_group(g)
A("/* End PBXGroup section */")
A("")

# PBXNativeTarget
A("/* Begin PBXNativeTarget section */")
A(f"\t\t{TARGET} /* Whisker */ = {{")
A(f"\t\t\tisa = PBXNativeTarget;")
A(f"\t\t\tbuildConfigurationList = {TCLIST} /* Build configuration list for PBXNativeTarget \"Whisker\" */;")
A(f"\t\t\tbuildPhases = (")
A(f"\t\t\t\t{SRC_PH} /* Sources */,")
A(f"\t\t\t\t{FRM_PH} /* Frameworks */,")
A(f"\t\t\t\t{RES_PH} /* Resources */,")
A(f"\t\t\t\t{EXT_EMBED_PH} /* Embed App Extensions */,")
A(f"\t\t\t);")
A(f"\t\t\tbuildRules = (")
A(f"\t\t\t);")
A(f"\t\t\tdependencies = (")
A(f"\t\t\t\t{EXT_DEP} /* PBXTargetDependency */,")
A(f"\t\t\t);")
A(f"\t\t\tname = Whisker;")
A(f"\t\t\tpackageProductDependencies = (")
A(f"\t\t\t);")
A(f"\t\t\tproductName = Whisker;")
A(f"\t\t\tproductReference = {APP_PR} /* Whisker.app */;")
A(f"\t\t\tproductType = \"com.apple.product-type.application\";")
A(f"\t\t}};")
A(f"\t\t{EXT_TARGET} /* WhiskerKeyboard */ = {{")
A(f"\t\t\tisa = PBXNativeTarget;")
A(f"\t\t\tbuildConfigurationList = {EXT_TCLIST} /* Build configuration list for PBXNativeTarget \"WhiskerKeyboard\" */;")
A(f"\t\t\tbuildPhases = (")
A(f"\t\t\t\t{EXT_SRC_PH} /* Sources */,")
A(f"\t\t\t\t{EXT_FRM_PH} /* Frameworks */,")
A(f"\t\t\t\t{EXT_RES_PH} /* Resources */,")
A(f"\t\t\t);")
A(f"\t\t\tbuildRules = (")
A(f"\t\t\t);")
A(f"\t\t\tdependencies = (")
A(f"\t\t\t);")
A(f"\t\t\tname = WhiskerKeyboard;")
A(f"\t\t\tproductName = WhiskerKeyboard;")
A(f"\t\t\tproductReference = {EXT_APP_PR} /* WhiskerKeyboard.appex */;")
A(f"\t\t\tproductType = \"com.apple.product-type.app-extension\";")
A(f"\t\t}};")
A("/* End PBXNativeTarget section */")
A("")

# PBXProject
A("/* Begin PBXProject section */")
A(f"\t\t{P} /* Project object */ = {{")
A(f"\t\t\tisa = PBXProject;")
A(f"\t\t\tattributes = {{")
A(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
A(f"\t\t\t\tLastUpgradeCheck = 2650;")
A(f"\t\t\t}};")
A(f"\t\t\tbuildConfigurationList = {PCLIST} /* Build configuration list for PBXProject \"Whisker\" */;")
A(f"\t\t\tcompatibilityVersion = \"Xcode 26.0\";")
A(f"\t\t\tdevelopmentRegion = en;")
A(f"\t\t\thasScannedForEncodings = 0;")
A(f"\t\t\tknownRegions = (")
A(f"\t\t\t\ten,")
A(f"\t\t\t\tBase,")
A(f"\t\t\t);")
A(f"\t\t\tmainGroup = {MGROUP};")
A(f"\t\t\tpackageReferences = (")
A(f"\t\t\t);")
A(f"\t\t\tproductRefGroup = {PGROUP} /* Products */;")
A(f"\t\t\tprojectDirPath = \"\";")
A(f"\t\t\tprojectRoot = \"\";")
A(f"\t\t\ttargets = (")
A(f"\t\t\t\t{TARGET} /* Whisker */,")
A(f"\t\t\t\t{EXT_TARGET} /* WhiskerKeyboard */,")
A(f"\t\t\t);")
A(f"\t\t}};")
A("/* End PBXProject section */")
A("")

# PBXResourcesBuildPhase
A("/* Begin PBXResourcesBuildPhase section */")
A(f"\t\t{RES_PH} /* Resources */ = {{")
A(f"\t\t\tisa = PBXResourcesBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tfiles = (")
for ref, bld, path in RESOURCES:
    name = os.path.basename(path)
    A(f"\t\t\t\t{bld} /* {name} in Resources */,")
A(f"\t\t\t);")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")
A("/* End PBXResourcesBuildPhase section */")
A("")

# PBXSourcesBuildPhase
A("/* Begin PBXSourcesBuildPhase section */")
A(f"\t\t{SRC_PH} /* Sources */ = {{")
A(f"\t\t\tisa = PBXSourcesBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tfiles = (")
for ref, bld, path in SOURCES:
    name = os.path.basename(path)
    A(f"\t\t\t\t{bld} /* {name} in Sources */,")
A(f"\t\t\t);")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")
A(f"\t\t{EXT_SRC_PH} /* Sources */ = {{")
A(f"\t\t\tisa = PBXSourcesBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tfiles = (")
for ref, bld, path in EXT_SOURCES:
    name = os.path.basename(path)
    A(f"\t\t\t\t{bld} /* {name} in Sources */,")
for file_ref, bld, path in EXT_SHARED_SOURCES:
    name = os.path.basename(path)
    A(f"\t\t\t\t{bld} /* {name} in Sources */,")
A(f"\t\t\t);")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")
A("/* End PBXSourcesBuildPhase section */")
A("")

# Extension resources build phase (empty for now)
A("/* Begin PBXResourcesBuildPhase section (extension) */")
A(f"\t\t{EXT_RES_PH} /* Resources */ = {{")
A(f"\t\t\tisa = PBXResourcesBuildPhase;")
A(f"\t\t\tbuildActionMask = 2147483647;")
A(f"\t\t\tfiles = (")
A(f"\t\t\t);")
A(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A(f"\t\t}};")

# XCBuildConfiguration
COMMON_PROJ = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}

COMMON_TARGET = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Whisker/Whisker.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_ASSET_PATHS": '"Whisker/Resources/Assets.xcassets"',
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Whisker/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": '"whisker"',
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": '"whisker records temporary audio on this iPhone and sends it to your configured transcription server."',
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": "app.whisker",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "iphoneos",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": '"1"',
    "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
    # Substituted into Whisker/Info.plist so RemoteMacSettings can seed
    # first-launch server endpoints. Empty by default (the public build seeds
    # nothing); set these env vars when regenerating the project to bake
    # personal defaults in without committing them.
    "WHISKER_DEFAULT_LOCAL_SERVER_URL": f'"{os.environ.get("WHISKER_DEFAULT_LOCAL_SERVER_URL", "")}"',
    "WHISKER_DEFAULT_FALLBACK_SERVER_URL": f'"{os.environ.get("WHISKER_DEFAULT_FALLBACK_SERVER_URL", "")}"',
}

EXT_TARGET_SETTINGS = {
    "CODE_SIGN_ENTITLEMENTS": "WhiskerKeyboard/WhiskerKeyboard.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "WhiskerKeyboard/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": '"whisker"',
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": "app.whisker.Keyboard",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": '"1"',
}

def emit_config(guid, name, settings, extra=None):
    merged = dict(settings)
    if extra:
        merged.update(extra)
    A(f"\t\t{guid} /* {name} */ = {{")
    A(f"\t\t\tisa = XCBuildConfiguration;")
    A(f"\t\t\tbuildSettings = {{")
    for k, v in sorted(merged.items()):
        A(f"\t\t\t\t{k} = {v};")
    A(f"\t\t\t}};")
    A(f"\t\t\tname = {name};")
    A(f"\t\t}};")

A("/* Begin XCBuildConfiguration section */")
emit_config(PDEBUG, "Debug", COMMON_PROJ,
    {"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES"})
emit_config(PRELEASE, "Release", COMMON_PROJ,
    {"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
     "ENABLE_NS_ASSERTIONS": "NO",
     "MTL_ENABLE_DEBUG_INFO": "NO",
     "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '""',
     "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
     "VALIDATE_PRODUCT": "YES"})
emit_config(TDEBUG, "Debug", COMMON_TARGET)
emit_config(TRELEASE, "Release", COMMON_TARGET)
emit_config(EXT_TDEBUG, "Debug", EXT_TARGET_SETTINGS)
emit_config(EXT_TRELEASE, "Release", EXT_TARGET_SETTINGS)
A("/* End XCBuildConfiguration section */")
A("")

# XCConfigurationList
A("/* Begin XCConfigurationList section */")
A(f"\t\t{PCLIST} /* Build configuration list for PBXProject \"Whisker\" */ = {{")
A(f"\t\t\tisa = XCConfigurationList;")
A(f"\t\t\tbuildConfigurations = (")
A(f"\t\t\t\t{PDEBUG} /* Debug */,")
A(f"\t\t\t\t{PRELEASE} /* Release */,")
A(f"\t\t\t);")
A(f"\t\t\tdefaultConfigurationIsVisible = 0;")
A(f"\t\t\tdefaultConfigurationName = Release;")
A(f"\t\t}};")
A(f"\t\t{TCLIST} /* Build configuration list for PBXNativeTarget \"Whisker\" */ = {{")
A(f"\t\t\tisa = XCConfigurationList;")
A(f"\t\t\tbuildConfigurations = (")
A(f"\t\t\t\t{TDEBUG} /* Debug */,")
A(f"\t\t\t\t{TRELEASE} /* Release */,")
A(f"\t\t\t);")
A(f"\t\t\tdefaultConfigurationIsVisible = 0;")
A(f"\t\t\tdefaultConfigurationName = Release;")
A(f"\t\t}};")
A(f"\t\t{EXT_TCLIST} /* Build configuration list for PBXNativeTarget \"WhiskerKeyboard\" */ = {{")
A(f"\t\t\tisa = XCConfigurationList;")
A(f"\t\t\tbuildConfigurations = (")
A(f"\t\t\t\t{EXT_TDEBUG} /* Debug */,")
A(f"\t\t\t\t{EXT_TRELEASE} /* Release */,")
A(f"\t\t\t);")
A(f"\t\t\tdefaultConfigurationIsVisible = 0;")
A(f"\t\t\tdefaultConfigurationName = Release;")
A(f"\t\t}};")
A("/* End XCConfigurationList section */")
A("")

A("\t};")
A(f"\trootObject = {P} /* Project object */;")
A("}")

pbxproj = "\n".join(lines)

out_dir = os.path.join(os.path.dirname(__file__), "Whisker.xcodeproj")
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "project.pbxproj")
with open(out_path, "w", encoding="utf-8") as f:
    f.write(pbxproj)

print(f"Wrote {out_path}")
print(f"  {len(SOURCES)} source files, {len(RESOURCES)} resource files")
print(f"  {len(EXT_SOURCES)} extension source files, {len(EXT_SHARED_SOURCES)} shared sources")
