// Linux type-check shim for Quartz. The Quick Look types live in the AppKit shim module
// (AppKit5.swift) because NSResponder must declare the overridable QLPreviewPanelController
// methods and Linux Swift cannot override methods declared in extensions. prep.py checks
// textually that every file using QL* types imports Quartz, as the real SDK requires.
@_exported import AppKit
