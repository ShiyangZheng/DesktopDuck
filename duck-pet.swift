#!/usr/bin/swift
import AppKit
import Foundation
import CoreGraphics
import UniformTypeIdentifiers

// ─── File Paths ────────────────────────────────────────────
let THOUGHTS_FILE = NSHomeDirectory() + "/.workbuddy/pet-thoughts.json"
let RESPONSE_FILE = NSHomeDirectory() + "/.workbuddy/pet-response.json"
let PREF_FILE     = NSHomeDirectory() + "/.workbuddy/duck-prefs.json"
let CONFIG_FILE   = NSHomeDirectory() + "/.workbuddy/duck-config.json"
let INBOX_FILE    = NSHomeDirectory() + "/.workbuddy/pet-inbox.txt"
let JOURNAL_FILE  = NSHomeDirectory() + "/.workbuddy/journal.json"
let POLL_INTERVAL: TimeInterval = 1.0
let BUBBLE_GAP: CGFloat = 2

// ─── Journal Templates ─────────────────────────────────────
let JOURNAL_TEMPLATES: [(String,String)] = [
    ("🧭 Odyssey Plan", """
You are a life design coach using the Odyssey Plan method from "Designing Your Life" by Burnett & Evans.
Guide the user to sketch THREE radically different 5-year futures:
1. Life One — "That Thing You Do": the path you're already on, amplified.
2. Life Two — "What If Path One Were Gone": what you'd do if your current path suddenly disappeared.
3. Life Three — "Wildcard": the life you'd live if money and image were no object.

For each, ask: What does a typical day look like? What skills are you using? Where do you live? What gives you meaning?
Be curious, non-judgmental, and encourage bold imagination. Keep responses warm and concise (2-3 sentences per question).
"""),

    ("🎡 Wheel of Life", """
You are a life balance coach using the Wheel of Life framework.
Guide the user to rate their satisfaction (1-10) across 8 dimensions:
- Career / Work
- Finances
- Health & Fitness
- Family & Friends
- Romance / Intimate Relationship
- Personal Growth & Learning
- Fun & Recreation
- Physical Environment / Home

First, ask the user to rate each area. Then explore the lowest-rated areas: What would a "10" look like? What's ONE small step you could take this week?
Be encouraging and practical. Use a gentle coaching tone. Keep responses concise.
"""),

    ("🎉 12 Month Celebration", """
You are a future-self celebration guide. Ask the user to imagine it is exactly 12 months from today, and they are at a celebration dinner with close friends. Each friend gives a toast celebrating a specific achievement from the past year.
Guide them to write these toasts addressing:
- Professional / academic achievements
- Personal growth breakthroughs
- Relationships deepened
- Health / wellness milestones
- Unexpected wins they couldn't have predicted

Start by setting the scene vividly, then ask questions one area at a time. Use warm, celebratory language. Help the user feel the pride and joy of their imagined future self.
"""),

    ("😨 Fear Setting", """
You are a Stoic coach using Tim Ferriss's Fear Setting exercise.
Guide the user through three columns for their biggest fear/decision:
Column 1 — DEFINE: What are the worst things that could happen? List 10-20 specific fears.
Column 2 — PREVENT: For each fear, what could you do to prevent it or reduce its likelihood?
Column 3 — REPAIR: If each fear came true, what could you do to repair the damage? Who could you ask for help?

Then ask: What might be the benefits of an attempt or partial success? What is the cost of inaction — emotionally, financially, physically — 6 months, 1 year, and 3 years from now?
Be direct but supportive. The goal is clarity through facing fears, not reassurance.
"""),

    ("👑 Solomon's Paradox", """
You are a wise advisor helping the user apply Solomon's Paradox — we are better at giving advice to others than to ourselves.
Ask the user to describe a current dilemma or difficult decision. Then ask them to step outside themselves:
"Imagine your best friend came to you with this exact situation. What advice would YOU give them? Be specific."

Follow up with:
- What assumptions might your friend be making that you can see but they cannot?
- What would the wisest person you know advise them?
- What would the 85-year-old version of you advise?

Help the user see their situation with the clarity of distance. Be warm, wise, and slightly playful.
"""),
]

let DEFAULT_JOURNAL_PROMPT = """
You are a mindful journaling companion. Ask the user about:
1) Current mood (1-10)
2) One thing they accomplished today
3) One thing they're grateful for
4) Any challenges they faced
Be warm, supportive, and concise. Respond in English.
"""

func resourcePath(_ name: String) -> String {
    let bundleDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
    let resDir = bundleDir + "/../Resources/"
    if FileManager.default.fileExists(atPath: resDir + name) { return resDir + name }
    return bundleDir + "/" + name
}
func scriptsDir() -> String {
    let exe = CommandLine.arguments[0]; let binDir = (exe as NSString).deletingLastPathComponent
    let resDir = binDir + "/../Resources/"
    if FileManager.default.fileExists(atPath: resDir + "pet-think.py") { return resDir }
    return binDir
}

// ─── Config ────────────────────────────────────────────────
class Config: NSObject {
    static let shared = Config()
    var scale: CGFloat = 2.0
    var windowLevel: Int = 2       // 0=bottom, 1=normal, 2=top (floating)
    var alwaysOnTop: Bool { windowLevel >= 2 }
    var idleGifPath: String = ""; var walkGifPath: String = ""
    var bubbleWidth: CGFloat = 240; var bubbleMaxHeight: CGFloat = 200
    var maxVisible: Int = 3; var bubbleTimeout: Double = 0
    var chatHistoryPath: String = (NSHomeDirectory() as NSString).expandingTildeInPath + "/.workbuddy/chat-history.json"
    var contextWindow: Int = 10; var compressThreshold: Int = 20
    var llmApiKey: String = ""; var llmModel: String = "MiniMax-M2.7"
    var llmUrl: String = "https://api.minimax.io/v1/chat/completions"
    var agentSync: Bool = true
    var userName: String = ""
    var aiName: String = "Duck"
    var journalTemplate: String = "🧭 Odyssey Plan"
    var journalPrompt: String = JOURNAL_TEMPLATES[0].1
    var windowX: CGFloat?; var windowY: CGFloat?; var windowW: CGFloat?; var windowH: CGFloat?
    var petType: String = "duck"
    var bubbleTextWidth: CGFloat { bubbleWidth - 52 }

    override init() { super.init(); load() }

    func load() {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: CONFIG_FILE)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String:Any] else { return }
        if let v = j["scale"] as? Double { scale = max(1.0, min(8.0, CGFloat(v))) }
        // Backward compat: old "alwaysOnTop" Bool -> new "windowLevel" Int
        if let v = j["windowLevel"] as? Int { windowLevel = max(0, min(2, v)) }
        else if let v = j["alwaysOnTop"] as? Bool { windowLevel = v ? 2 : 1 }
        if let v = j["idleGifPath"] as? String { idleGifPath = v }
        if let v = j["walkGifPath"] as? String { walkGifPath = v }
        if let v = j["bubbleWidth"] as? Double { bubbleWidth = max(160, min(400, CGFloat(v))) }
        if let v = j["bubbleMaxHeight"] as? Double { bubbleMaxHeight = max(80, min(600, CGFloat(v))) }
        if let v = j["maxVisible"] as? Int { maxVisible = max(1, min(10, v)) }
        if let v = j["bubbleTimeout"] as? Double { bubbleTimeout = max(0, v) }
        if let v = j["chatHistoryPath"] as? String { chatHistoryPath = v }
        if let v = j["contextWindow"] as? Int { contextWindow = max(0, min(100, v)) }
        if let v = j["compressThreshold"] as? Int { compressThreshold = max(5, min(500, v)) }
        if let v = j["minimax_api_key"] as? String { llmApiKey = v }
        else if let v = j["openai_api_key"] as? String { llmApiKey = v }
        if let v = j["model"] as? String { llmModel = v }
        if let v = j["minimax_url"] as? String { llmUrl = v }
        if let v = j["agentSync"] as? Bool { agentSync = v }
        if let v = j["user_name"] as? String { userName = v }
        if let v = j["ai_name"] as? String { aiName = v }
        if let v = j["journalTemplate"] as? String { journalTemplate = v }
        if let v = j["journalPrompt"] as? String { journalPrompt = v }
        if let v = j["x"] as? Double { windowX = CGFloat(v) }
        if let v = j["y"] as? Double { windowY = CGFloat(v) }
        if let v = j["w"] as? Double { windowW = CGFloat(v) }
        if let v = j["h"] as? Double { windowH = CGFloat(v) }
    }

    func save() {
        var j: [String:Any] = [
            "scale": Double(scale), "windowLevel": windowLevel,
            "bubbleWidth": Double(bubbleWidth), "bubbleMaxHeight": Double(bubbleMaxHeight),
            "maxVisible": maxVisible, "bubbleTimeout": bubbleTimeout,
            "model": llmModel, "minimax_url": llmUrl,
            "chatHistoryPath": chatHistoryPath, "contextWindow": contextWindow,
            "compressThreshold": compressThreshold,             "agentSync": agentSync,
            "journalTemplate": journalTemplate, "journalPrompt": journalPrompt,
            "user_name": userName, "ai_name": aiName,
        ]
        if !llmApiKey.isEmpty { j["minimax_api_key"] = llmApiKey }
        if !idleGifPath.isEmpty { j["idleGifPath"] = idleGifPath }
        if !walkGifPath.isEmpty { j["walkGifPath"] = walkGifPath }
        if let x = windowX { j["x"] = Double(x) }; if let y = windowY { j["y"] = Double(y) }
        if let w = windowW { j["w"] = Double(w) }; if let h = windowH { j["h"] = Double(h) }
        try? JSONSerialization.data(withJSONObject: j, options: .prettyPrinted)
            .write(to: URL(fileURLWithPath: CONFIG_FILE))
        try? JSONSerialization.data(withJSONObject: j).write(to: URL(fileURLWithPath: PREF_FILE))
    }

    func clearHistory() {
        try? "[]".write(toFile: THOUGHTS_FILE, atomically: true, encoding: .utf8)
        try? "".write(toFile: INBOX_FILE, atomically: true, encoding: .utf8)
        try? "[]".write(toFile: chatHistoryPath, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/.workbuddy/pet-inbox-state.json")
    }
}

var cfg = Config.shared
var BUBBLE_WIDTH: CGFloat { cfg.bubbleWidth }
var BUBBLE_TEXT_WIDTH: CGFloat { cfg.bubbleTextWidth }
var MAX_VISIBLE: Int { cfg.maxVisible }
var MAX_BUBBLE_HEIGHT: CGFloat { cfg.bubbleMaxHeight }

func loadSize() -> CGFloat {
    for i in 0..<CommandLine.arguments.count-1 {
        if CommandLine.arguments[i] == "--scale", let s = Double(CommandLine.arguments[i+1]) { return max(1.0, min(8.0, CGFloat(s))) }
    }
    return cfg.scale
}
var currentScale = loadSize()

func calcBubbleHeight(_ text: String) -> CGFloat {
    let font = NSFont(name: "PingFang SC", size: 13) ?? NSFont.systemFont(ofSize: 13)
    let r = (text as NSString).boundingRect(with: NSSize(width: BUBBLE_TEXT_WIDTH, height: 999),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    return min(max(ceil(r.height) + 16, 30), MAX_BUBBLE_HEIGHT)
}
func calcBubbleContentHeight(_ text: String) -> CGFloat {
    let font = NSFont(name: "PingFang SC", size: 13) ?? NSFont.systemFont(ofSize: 13)
    let r = (text as NSString).boundingRect(with: NSSize(width: BUBBLE_TEXT_WIDTH, height: 999),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    return max(ceil(r.height) + 16, 30)
}
func makeBubbleWin(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> NSWindow {
    let bw = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h),
        styleMask: .borderless, backing: .buffered, defer: false)
    bw.isOpaque = false; bw.backgroundColor  = .clear; bw.level  = .floating
    bw.hasShadow = false; bw.ignoresMouseEvents = false; bw.isReleasedWhenClosed = false
    return bw
}

// ─── BubbleView ────────────────────────────────────────────
class BubbleView: NSView {
    var text: String = ""; var btype: String = "thinking"; var alpha: CGFloat = 1
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let colors: [String:(CGFloat,CGFloat,CGFloat)] = [
            "thinking":(1,0.97,0.88),"done":(0.91,0.96,0.91),"found":(0.91,0.96,0.91),
            "searching":(0.89,0.95,0.99),"writing":(0.93,0.91,0.97),"working":(0.89,0.95,0.99),
            "analyzing":(1,0.97,0.88)]
        let bg = colors[btype] ?? (1,1,0.96)
        ctx.setFillColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 0.88*alpha)
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.fillPath()
        let font = NSFont(name: "PingFang SC", size: 13) ?? NSFont.systemFont(ofSize: 13)
        let r = NSRect(x: 12, y: 6, width: BUBBLE_TEXT_WIDTH, height: bounds.height-12)
        (text as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .foregroundColor: NSColor(red:0.2,green:0.2,blue:0.2,alpha:alpha)])
    }
}

// ─── ButtonOverlay ─────────────────────────────────────────
class ButtonOverlay: NSView {
    var onClose: (() -> Void)?; var onReply: (() -> Void)?; var alpha: CGFloat = 1
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cx = bounds.width-24, cy = bounds.height-22
        ctx.setFillColor(red:0.5,green:0.5,blue:0.5,alpha:0.25*alpha)
        ctx.addPath(CGPath(ellipseIn: NSRect(x:cx,y:cy,width:20,height:20),transform:nil)); ctx.fillPath()
        NSAttributedString(string:"✕",attributes:[.font:NSFont.boldSystemFont(ofSize:12),.foregroundColor:NSColor(white:0.35,alpha:alpha)]).draw(at:NSPoint(x:cx+4,y:cy+2))
        let rx = bounds.width-44
        ctx.setFillColor(red:0.4,green:0.5,blue:0.8,alpha:0.2*alpha)
        ctx.addPath(CGPath(ellipseIn: NSRect(x:rx,y:cy,width:18,height:18),transform:nil)); ctx.fillPath()
        NSAttributedString(string:"↩",attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor(red:0.3,green:0.45,blue:0.8,alpha:alpha)]).draw(at:NSPoint(x:rx+2,y:cy+2))
    }
    override func mouseDown(with e: NSEvent) {
        let loc = convert(e.locationInWindow,from:nil)
        let cx = bounds.width-24, cy = bounds.height-22
        if NSPointInRect(loc,NSRect(x:cx,y:cy,width:20,height:20)) { onClose?(); return }
        if NSPointInRect(loc,NSRect(x:bounds.width-44,y:cy,width:18,height:20)) { onReply?(); return }
    }
}

// ─── FoldView / PermView ───────────────────────────────────
class FoldView: NSView {
    var text = ""; var onTap: (()->Void)?
    override func draw(_ d: NSRect) {
        super.draw(d)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.setFillColor(red:0.85,green:0.85,blue:0.85,alpha:0.75)
        c.addPath(CGPath(roundedRect:bounds,cornerWidth:6,cornerHeight:6,transform:nil)); c.fillPath()
        let f = NSFont(name:"PingFang SC",size:11) ?? .systemFont(ofSize:11)
        let tr = (text as NSString).boundingRect(with:NSSize(width:bounds.width-12,height:20),options:[],attributes:[.font:f])
        NSAttributedString(string:text,attributes:[.font:f,.foregroundColor:NSColor(white:0.3,alpha:1)]).draw(at:NSPoint(x:(bounds.width-tr.width)/2,y:(bounds.height-tr.height)/2))
    }
    override func mouseDown(with e: NSEvent) { onTap?() }
}
class PermView: NSView {
    var text = ""; var onResp:((String)->Void)?; var allowR = NSRect.zero, denyR = NSRect.zero
    override func draw(_ d: NSRect) {
        super.draw(d)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.setFillColor(red:1,green:0.95,blue:0.9,alpha:0.88)
        c.addPath(CGPath(roundedRect:bounds,cornerWidth:10,cornerHeight:10,transform:nil)); c.fillPath()
        let f = NSFont(name:"PingFang SC",size:12) ?? .systemFont(ofSize:12)
        NSAttributedString(string:text,attributes:[.font:f,.foregroundColor:NSColor(red:0.2,green:0.2,blue:0.2,alpha:1)]).draw(at:NSPoint(x:10,y:bounds.height-24))
        let bw:CGFloat = 70,bh:CGFloat = 24,by:CGFloat = 6
        denyR = NSRect(x:bounds.width-bw*2-20,y:by,width:bw,height:bh)
        allowR = NSRect(x:bounds.width-bw-10,y:by,width:bw,height:bh)
        c.setFillColor(red:0.85,green:0.3,blue:0.3,alpha:0.85)
        c.addPath(CGPath(roundedRect:denyR,cornerWidth:6,cornerHeight:6,transform:nil)); c.fillPath()
        NSAttributedString(string:"Deny",attributes:[.font:NSFont.boldSystemFont(ofSize:12),.foregroundColor:NSColor.white]).draw(at:NSPoint(x:denyR.origin.x+18,y:by+5))
        c.setFillColor(red:0.3,green:0.7,blue:0.3,alpha:0.9)
        c.addPath(CGPath(roundedRect:allowR,cornerWidth:6,cornerHeight:6,transform:nil)); c.fillPath()
        NSAttributedString(string:"Allow",attributes:[.font:NSFont.boldSystemFont(ofSize:12),.foregroundColor:NSColor.white]).draw(at:NSPoint(x:allowR.origin.x+18,y:by+5))
    }
    override func mouseDown(with e: NSEvent) {
        let loc = convert(e.locationInWindow,from:nil)
        if NSPointInRect(loc,allowR) { onResp?("allow") }
        if NSPointInRect(loc,denyR) { onResp?("deny") }
    }
}
class ChatTextView: NSTextView {
    var onSubmit: (()->Void)?
    // Use doCommand(by:) instead of overriding keyDown — preserves IME compatibility
    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            if !hasMarkedText() {
                onSubmit?()
                return
            }
        }
        super.doCommand(by: selector)
    }
}

// ─── Journal View ──────────────────────────────────────────
class JournalWindow: NSWindowController {
    var templatePopup: NSPopUpButton!
    var docView: NSTextView!
    var statusLabel: NSTextField!

    convenience init() {
        let w:CGFloat = 520, h:CGFloat = 580
        let win = NSWindow(contentRect:NSRect(x:0,y:0,width:w,height:h),
            styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        win.title = "My Journal"; win.isReleasedWhenClosed = false; win.center()
        self.init(window:win); buildUI(NSSize(width:w,height:h)); refreshDocument()
    }

    func buildUI(_ sz: NSSize) {
        guard let win = window else { return }
        let w = sz.width, m: CGFloat = 16

        // Template selector
        let tplLabel = NSTextField(frame: NSRect(x: m, y: sz.height - 24, width: 70, height: 18))
        tplLabel.stringValue = "Template:"; tplLabel.isBezeled = false; tplLabel.drawsBackground = false
        tplLabel.isEditable = false; tplLabel.font = .systemFont(ofSize: 11); tplLabel.textColor = .secondaryLabelColor
        win.contentView?.addSubview(tplLabel)

        templatePopup = NSPopUpButton(frame: NSRect(x: m + 70, y: sz.height - 28, width: 200, height: 22), pullsDown: false)
        for (name,_) in JOURNAL_TEMPLATES { templatePopup.addItem(withTitle: name) }
        templatePopup.selectItem(withTitle: cfg.journalTemplate)
        templatePopup.target = self; templatePopup.action = #selector(templateChanged)
        win.contentView?.addSubview(templatePopup)

        // Buttons
        let btnY = sz.height - 58
        let refreshBtn = NSButton(frame: NSRect(x: m, y: btnY, width: 90, height: 24))
        refreshBtn.title = "Refresh"; refreshBtn.bezelStyle = .rounded; refreshBtn.font = .systemFont(ofSize: 11)
        refreshBtn.target = self; refreshBtn.action = #selector(refresh(_:))
        win.contentView?.addSubview(refreshBtn)

        let sessionBtn = NSButton(frame: NSRect(x: m + 100, y: btnY, width: 100, height: 24))
        sessionBtn.title = "+ Session"; sessionBtn.bezelStyle = .rounded; sessionBtn.font = .systemFont(ofSize: 11)
        sessionBtn.target = self; sessionBtn.action = #selector(newEntry(_:))
        win.contentView?.addSubview(sessionBtn)

        let continueBtn = NSButton(frame: NSRect(x: m + 210, y: btnY, width: 90, height: 24))
        continueBtn.title = "Continue"; continueBtn.bezelStyle = .rounded; continueBtn.font = .systemFont(ofSize: 11)
        continueBtn.target = self; continueBtn.action = #selector(continueSession)
        win.contentView?.addSubview(continueBtn)

        // Document view
        let docScroll = NSScrollView(frame: NSRect(x: m, y: 40, width: w - m * 2, height: sz.height - 108))
        docScroll.drawsBackground = false; docScroll.hasVerticalScroller = true
        docScroll.borderType = .bezelBorder; docScroll.autohidesScrollers = true
        docView = NSTextView(frame: NSRect(x: 0, y: 0, width: w - m * 2 - 16, height: 400))
        docView.isEditable = false; docView.isRichText = false
        docView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        docView.textColor = .labelColor; docView.backgroundColor = .clear
        docScroll.documentView = docView
        win.contentView?.addSubview(docScroll)

        // Status
        statusLabel = NSTextField(frame: NSRect(x: m, y: 8, width: w - m * 2, height: 18))
        statusLabel.isBezeled = false; statusLabel.drawsBackground = false; statusLabel.isEditable = false
        statusLabel.font = .systemFont(ofSize: 10); statusLabel.textColor = .secondaryLabelColor
        win.contentView?.addSubview(statusLabel)
    }

    func refreshDocument() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: JOURNAL_FILE)),
              let journal = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = journal["documents"] as? [String: [String: Any]] else {
            docView.string = "# No journal entries yet.\n\nStart a session from Preferences or right-click the duck."
            statusLabel.stringValue = "0 document(s)"
            return
        }
        let tpl = templatePopup.titleOfSelectedItem ?? cfg.journalTemplate
        if let doc = docs[tpl], let content = doc["content"] as? String, !content.isEmpty {
            docView.string = content
            let sessions = (doc["sessions"] as? [[String: Any]]) ?? []
            let updated = doc["updated_at"] as? String ?? ""
            let df = ISO8601DateFormatter(); df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var timeStr = updated
            if let d = df.date(from: updated) ?? ISO8601DateFormatter().date(from: updated) {
                let fmt = DateFormatter(); fmt.dateFormat = "MMM d, HH:mm"
                timeStr = fmt.string(from: d)
            }
            statusLabel.stringValue = "\(sessions.count) session(s) · Updated \(timeStr)"
        } else {
            docView.string = "# \(tpl)\n\nNo content yet. Start a journal session to begin."
            statusLabel.stringValue = "0 sessions"
        }
    }

    @objc func templateChanged() {
        cfg.journalTemplate = templatePopup.titleOfSelectedItem ?? JOURNAL_TEMPLATES[0].0
        cfg.save()
        refreshDocument()
    }
    @objc func newEntry(_ s: Any?) { AppDelegate.instance?.duck?.startJournalSession() }
    @objc func continueSession() { AppDelegate.instance?.duck?.startJournalSession() }

    @objc func refresh(_ s: Any?) {
        statusLabel.stringValue = "Summarizing..."
        let sp = scriptsDir() + "pet-journal-summary.py"
        DispatchQueue.global().async {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            t.arguments = [sp, "--all"]
            try? t.run(); t.waitUntilExit()
            DispatchQueue.main.async { self.refreshDocument() }
        }
    }

    override func showWindow(_ s: Any?) { window?.center(); super.showWindow(s); refreshDocument() }
}

// ─── Settings Window ──────────────────────────────────────

// ─── SpritePreviewView ────────────────────────────
// ─── SpritePreviewView with draggable grid ──────
class SpritePreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var rows: Int = 1 { didSet { if oldValue != rows { resetCustomSplits() }; needsDisplay = true } }
    var cols: Int = 5 { didSet { if oldValue != cols { resetCustomSplits() }; needsDisplay = true } }
    var showGrid: Bool = true { didSet { needsDisplay = true } }

    // Custom grid splits (fractions 0.0…1.0 of image dim), nil = equal division
    var customRowSplits: [CGFloat]? { didSet { needsDisplay = true } }
    var customColSplits: [CGFloat]? { didSet { needsDisplay = true } }

    private var dragLine: (horiz: Bool, idx: Int)? = nil
    private var dragStartPt: NSPoint = .zero
    private var dragStartVal: CGFloat = 0
    private var _imgRect: NSRect = .zero  // cached image rect

    let lineHitRadius: CGFloat = 10

    func resetCustomSplits() { customRowSplits = nil; customColSplits = nil }
    var hasCustomSplits: Bool { customRowSplits != nil || customColSplits != nil }

    func rowSplits() -> [CGFloat] {
        if let s = customRowSplits, s.count == rows + 1 { return s }
        return (0...rows).map { CGFloat($0) / CGFloat(max(rows, 1)) }
    }
    func colSplits() -> [CGFloat] {
        if let s = customColSplits, s.count == cols + 1 { return s }
        return (0...cols).map { CGFloat($0) / CGFloat(max(cols, 1)) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = image else {
            NSColor(white: 0.12, alpha: 1).set(); bounds.fill(); return
        }
        let bw = bounds.width, bh = bounds.height
        let iw = img.size.width, ih = img.size.height
        let scale = min(bw / iw, bh / ih)
        let dw = iw * scale, dh = ih * scale
        let dx = (bw - dw) / 2, dy = (bh - dh) / 2
        _imgRect = NSRect(x: dx, y: dy, width: dw, height: dh)
        img.draw(in: _imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        guard showGrid, rows > 0, cols > 0 else { return }

        let rFracs = rowSplits(), cFracs = colSplits()
        // fraction 0=top of image → view maxY, 1=bottom → view minY
        let rowYs = rFracs.map { dy + (1.0 - $0) * dh }
        let colXs = cFracs.map { dx + $0 * dw }

        // Grid lines
        let lineColor = NSColor(red: 0.31, green: 0.76, blue: 0.97, alpha: 0.55)
        lineColor.set()
        for x in colXs {
            let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: dy))
            p.line(to: NSPoint(x: x, y: dy + dh)); p.stroke()
        }
        for y in rowYs {
            let p = NSBezierPath(); p.move(to: NSPoint(x: dx, y: y))
            p.line(to: NSPoint(x: dx + dw, y: y)); p.stroke()
        }

        // Drag handles on interior lines
        let handleColor = NSColor(red: 0.31, green: 0.76, blue: 0.97, alpha: 0.85)
        handleColor.set()
        for i in 1..<rows {
            let y = rowYs[i]
            NSBezierPath(roundedRect: NSRect(x: dx + dw/2 - 24, y: y - 3, width: 48, height: 6),
                         xRadius: 3, yRadius: 3).fill()
        }
        for i in 1..<cols {
            let x = colXs[i]
            NSBezierPath(roundedRect: NSRect(x: x - 3, y: dy + dh/2 - 24, width: 6, height: 48),
                         xRadius: 3, yRadius: 3).fill()
        }

        // Frame numbers in bottom-left of each cell
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor(red: 0.31, green: 0.76, blue: 0.97, alpha: 1.0)
        ]
        for r in 0..<rows {
            for c in 0..<cols {
                let num = r * cols + c + 1
                let t = NSAttributedString(string: String(num), attributes: attrs)
                t.draw(at: NSPoint(x: colXs[c] + 2, y: rowYs[r + 1] + 2))
            }
        }
    }

    // MARK: Mouse dragging

    override func mouseDown(with event: NSEvent) {
        guard showGrid, image != nil else { super.mouseDown(with: event); return }
        let pt = convert(event.locationInWindow, from: nil)
        let r = _imgRect; guard r.contains(pt) else { super.mouseDown(with: event); return }

        let rFracs = rowSplits(), cFracs = colSplits()
        let rowYs = rFracs.map { r.minY + (1.0 - $0) * r.height }
        let colXs = cFracs.map { r.minX + $0 * r.width }

        for i in 0...rows where abs(pt.y - rowYs[i]) < lineHitRadius {
            dragLine = (true, i); dragStartPt = pt
            dragStartVal = customRowSplits?[i] ?? rFracs[i]; return
        }
        for i in 0...cols where abs(pt.x - colXs[i]) < lineHitRadius {
            dragLine = (false, i); dragStartPt = pt
            dragStartVal = customColSplits?[i] ?? cFracs[i]; return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dl = dragLine else { super.mouseDragged(with: event); return }
        let pt = convert(event.locationInWindow, from: nil)
        let r = _imgRect; let n = CGFloat(max(dl.horiz ? rows : cols, 1))

        if dl.horiz {
            let delta = (dragStartPt.y - pt.y) / r.height  // drag up → smaller fraction
            var v = dragStartVal + delta
            let lo: CGFloat = dl.idx == 0 ? 0 : ((customRowSplits?[dl.idx - 1]) ?? (CGFloat(dl.idx - 1) / n))
            let hi: CGFloat = dl.idx == rows ? 1 : ((customRowSplits?[dl.idx + 1]) ?? (CGFloat(dl.idx + 1) / n))
            v = max(lo + 0.015, min(hi - 0.015, v))
            if customRowSplits == nil { customRowSplits = (0...rows).map { CGFloat($0) / n } }
            customRowSplits![dl.idx] = v; needsDisplay = true
        } else {
            let delta = (pt.x - dragStartPt.x) / r.width
            var v = dragStartVal + delta
            let lo: CGFloat = dl.idx == 0 ? 0 : ((customColSplits?[dl.idx - 1]) ?? (CGFloat(dl.idx - 1) / n))
            let hi: CGFloat = dl.idx == cols ? 1 : ((customColSplits?[dl.idx + 1]) ?? (CGFloat(dl.idx + 1) / n))
            v = max(lo + 0.015, min(hi - 0.015, v))
            if customColSplits == nil { customColSplits = (0...cols).map { CGFloat($0) / n } }
            customColSplits![dl.idx] = v; needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) { dragLine = nil }
}

// ─── SpritesheetEditorWindow ──────────────────────
class SpritesheetEditorWindow: NSWindowController {
    var promptField: NSTextField!
    var rowsField: NSTextField!, colsField: NSTextField!
    var delaySlider: NSSlider!, canvasSlider: NSSlider!
    var previewView: SpritePreviewView!
    var thumbStrip: NSView!
    var statusLabel: NSTextField!
    var genButton: NSButton!, spinner: NSProgressIndicator!
    var animScrollView: NSScrollView!
    var generatedStates: [String: String] = [:]
    var currentSpritesheetPath: String = ""

    convenience init() {
        let w: CGFloat = 540, h: CGFloat = 700
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = "Spritesheet Editor"; win.isReleasedWhenClosed = false; win.center()
        self.init(window: win); buildUI(NSSize(width: w, height: h))
    }

    func buildUI(_ sz: NSSize) {
        guard let win = window else { return }
        let w = sz.width, m: CGFloat = 14
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: sz.height))
        sv.drawsBackground = false; sv.hasVerticalScroller = true; sv.borderType = .noBorder; sv.autohidesScrollers = true
        let body = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 1050)); var y: CGFloat = 1030

        func sec(_ t: String) {
            let lb = NSTextField(frame: NSRect(x: m, y: y - 14, width: w - m * 2, height: 14))
            lb.stringValue = t; lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = .boldSystemFont(ofSize: 11); lb.textColor = .labelColor; y -= 20; body.addSubview(lb)
        }
        func sub(_ t: String) {
            let lb = NSTextField(frame: NSRect(x: m, y: y - 12, width: w - m * 2, height: 12))
            lb.stringValue = t; lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = .systemFont(ofSize: 9); lb.textColor = .secondaryLabelColor; y -= 14; body.addSubview(lb)
        }

        // Prompt
        sec("Character Description")
        promptField = NSTextField(frame: NSRect(x: m, y: y - 36, width: w - m * 2, height: 36))
        promptField.stringValue = "cute duck, pixel art style"
        promptField.isBezeled = true; promptField.bezelStyle = .squareBezel
        promptField.font = .systemFont(ofSize: 12); y -= 42; body.addSubview(promptField)

        // Grid
        sec("Grid Controls (adjust rows x frames to match your spritesheet)")
        let gRow = NSView(frame: NSRect(x: m, y: y - 26, width: w - m * 2, height: 26))
        let rl = NSTextField(frame: NSRect(x: 0, y: 4, width: 36, height: 18))
        rl.stringValue = "Rows:"; rl.isBezeled = false; rl.drawsBackground = false; rl.isEditable = false
        rl.font = .systemFont(ofSize: 10); rl.textColor = .secondaryLabelColor; gRow.addSubview(rl)
        rowsField = NSTextField(frame: NSRect(x: 38, y: 0, width: 40, height: 22))
        rowsField.stringValue = "1"; rowsField.isBezeled = true; rowsField.bezelStyle = .squareBezel
        rowsField.font = .systemFont(ofSize: 11); rowsField.target = self; rowsField.action = #selector(gridParamsChanged)
        gRow.addSubview(rowsField)
        let fl = NSTextField(frame: NSRect(x: 94, y: 4, width: 42, height: 18))
        fl.stringValue = "Frames:"; fl.isBezeled = false; fl.drawsBackground = false; fl.isEditable = false
        fl.font = .systemFont(ofSize: 10); fl.textColor = .secondaryLabelColor; gRow.addSubview(fl)
        colsField = NSTextField(frame: NSRect(x: 138, y: 0, width: 40, height: 22))
        colsField.stringValue = "5"; colsField.isBezeled = true; colsField.bezelStyle = .squareBezel
        colsField.font = .systemFont(ofSize: 11); colsField.target = self; colsField.action = #selector(gridParamsChanged)
        gRow.addSubview(colsField)
        let gridCheck = NSButton(checkboxWithTitle: "Show Grid", target: self, action: #selector(toggleGrid))
        gridCheck.frame = NSRect(x: 200, y: 2, width: 90, height: 20); gridCheck.state = .on; gRow.addSubview(gridCheck)
        let resetBtn = NSButton(frame: NSRect(x: 298, y: 0, width: 80, height: 22))
        resetBtn.title = "Reset Grid"; resetBtn.bezelStyle = .inline; resetBtn.font = .systemFont(ofSize: 10)
        resetBtn.target = self; resetBtn.action = #selector(resetGridLines); gRow.addSubview(resetBtn)
        y -= 32; body.addSubview(gRow)

        sub("Tip: adjust Rows and Frames to match your spritesheet's actual grid")

        // Sliders
        sec("Animation")
        func mkSld(_ lb: String, _ t: Int, _ mn: Double, _ mx: Double, _ v: Double, _ sf: String) {
            let rw = NSView(frame: NSRect(x: m, y: y - 20, width: w - m * 2, height: 20))
            let l = NSTextField(frame: NSRect(x: 0, y: 1, width: 76, height: 16)); l.stringValue = lb
            l.isBezeled = false; l.drawsBackground = false; l.isEditable = false; l.font = .systemFont(ofSize: 10)
            l.textColor = .secondaryLabelColor; rw.addSubview(l)
            let s = NSSlider(frame: NSRect(x: 80, y: 0, width: w - m * 2 - 126, height: 20))
            s.minValue = mn; s.maxValue = mx; s.doubleValue = v; s.tag = t; s.target = self; s.action = #selector(sliderChanged); rw.addSubview(s)
            let vl = NSTextField(frame: NSRect(x: w - m * 2 - 44, y: 1, width: 44, height: 16))
            vl.isBezeled = false; vl.drawsBackground = false; vl.isEditable = false; vl.font = .systemFont(ofSize: 10)
            vl.textColor = .labelColor; vl.tag = t + 100; vl.stringValue = sf; rw.addSubview(vl)
            y -= 24; body.addSubview(rw)
            if t == 1 { delaySlider = s } else { canvasSlider = s }
        }
        mkSld("Frame Delay", 1, 50, 500, 100, "100ms")
        mkSld("Canvas Size", 2, 64, 160, 80, "80px")

        // Buttons
        let btnRow = NSView(frame: NSRect(x: m, y: y - 30, width: w - m * 2, height: 30))
        genButton = NSButton(frame: NSRect(x: 0, y: 0, width: 140, height: 30))
        genButton.title = "Generate"; genButton.bezelStyle = .rounded; genButton.font = .systemFont(ofSize: 12, weight: .medium)
        genButton.target = self; genButton.action = #selector(generateSpritesheet); btnRow.addSubview(genButton)
        spinner = NSProgressIndicator(frame: NSRect(x: 148, y: 7, width: 16, height: 16))
        spinner.style = .spinning; spinner.isDisplayedWhenStopped = false; btnRow.addSubview(spinner)
        let upl = NSButton(frame: NSRect(x: 172, y: 0, width: 100, height: 30))
        upl.title = "Upload"; upl.bezelStyle = .rounded; upl.font = .systemFont(ofSize: 12)
        upl.target = self; upl.action = #selector(uploadSpritesheet); btnRow.addSubview(upl)
        let cnv = NSButton(frame: NSRect(x: 280, y: 0, width: 100, height: 30))
        cnv.title = "Convert"; cnv.bezelStyle = .rounded; cnv.font = .systemFont(ofSize: 12)
        cnv.target = self; cnv.action = #selector(convertToGif); btnRow.addSubview(cnv)
        y -= 38; body.addSubview(btnRow)

        // Preview
        sec("Spritesheet Preview (grid shows frame boundaries)")
        previewView = SpritePreviewView(frame: NSRect(x: m, y: y - 200, width: w - m * 2, height: 200))
        previewView.wantsLayer = true; previewView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        previewView.layer?.cornerRadius = 6; previewView.showGrid = true
        y -= 210; body.addSubview(previewView)

        // Thumbnails
        sec("Frame Preview (first 12 frames)")
        thumbStrip = NSView(frame: NSRect(x: m, y: y - 70, width: w - m * 2, height: 70))
        y -= 78; body.addSubview(thumbStrip)

        // Animation Preview (after Convert)
        sec("Animation Preview (generated GIFs)")
        let animScroll = NSScrollView(frame: NSRect(x: m, y: y - 200, width: w - m * 2, height: 200))
        animScroll.drawsBackground = false; animScroll.hasVerticalScroller = false
        animScroll.hasHorizontalScroller = true; animScroll.borderType = .noBorder; animScroll.autohidesScrollers = true
        let animStrip = NSView(frame: NSRect(x: 0, y: 0, width: (w - m * 2) * 2, height: 200))
        animStrip.wantsLayer = true; animStrip.layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        animStrip.layer?.cornerRadius = 6
        let animLabel = NSTextField(frame: NSRect(x: 10, y: 60, width: animStrip.frame.width - 20, height: 16))
        animLabel.stringValue = "GIF previews will appear here after Convert"
        animLabel.isBezeled = false; animLabel.drawsBackground = false; animLabel.isEditable = false
        animLabel.font = .systemFont(ofSize: 10); animLabel.textColor = .secondaryLabelColor
        animLabel.alignment = .center; animLabel.tag = 9001; animStrip.addSubview(animLabel)
        animScroll.documentView = animStrip; animScrollView = animScroll
        y -= 208; body.addSubview(animScroll)

        // Actions
        let actRow = NSView(frame: NSRect(x: m, y: y - 30, width: w - m * 2, height: 30))
        let go = NSButton(frame: NSRect(x: 0, y: 0, width: 110, height: 30))
        go.title = "Apply to Pet"; go.bezelStyle = .rounded; go.font = .systemFont(ofSize: 12, weight: .medium)
        go.target = self; go.action = #selector(applyToPet); actRow.addSubview(go)
        let dk = NSButton(frame: NSRect(x: 118, y: 0, width: 40, height: 30))
        dk.title = "\u{1F986}"; dk.bezelStyle = .rounded; dk.font = .systemFont(ofSize: 14)
        dk.target = self; dk.action = #selector(resetToDuck); actRow.addSubview(dk)
        let cp = NSButton(frame: NSRect(x: 164, y: 0, width: 40, height: 30))
        cp.title = "\u{1F9AB}"; cp.bezelStyle = .rounded; cp.font = .systemFont(ofSize: 14)
        cp.target = self; cp.action = #selector(resetToCapybara); actRow.addSubview(cp)
        y -= 38; body.addSubview(actRow)

        statusLabel = NSTextField(frame: NSRect(x: m, y: y - 16, width: w - m * 2, height: 16))
        statusLabel.isBezeled = false; statusLabel.drawsBackground = false; statusLabel.isEditable = false
        statusLabel.font = .systemFont(ofSize: 10); statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Adjust Rows x Frames to match your spritesheet, then Convert to GIF."
        y -= 16; body.addSubview(statusLabel)

        sv.documentView = body; win.contentView?.addSubview(sv)
    }

    @objc func toggleGrid(_ s: NSButton) { previewView.showGrid = (s.state == .on) }

    @objc func gridParamsChanged() {
        previewView.rows = Int(rowsField.stringValue) ?? 1
        previewView.cols = Int(colsField.stringValue) ?? 5
        updateFrameThumbnails()
    }

    @objc func sliderChanged(_ s: NSSlider) {
        if let v = body?.viewWithTag(s.tag + 100) as? NSTextField {
            v.stringValue = s.tag == 1 ? "\(Int(s.doubleValue))ms" : "\(Int(s.doubleValue))px"
        }
    }

    func updateFrameThumbnails() {
        thumbStrip.subviews.forEach { $0.removeFromSuperview() }
        guard let img = previewView.image else { return }
        let rows = Int(rowsField.stringValue) ?? 1
        let cols = Int(colsField.stringValue) ?? 5
        let iw = img.size.width, ih = img.size.height
        let rFracs = previewView.rowSplits()
        let cFracs = previewView.colSplits()
        var x: CGFloat = 0; let count = min(rows * cols, 12)
        for i in 0..<count {
            let r = i / cols, c = i % cols
            if r >= rows { break }
            // Use custom splits: fraction 0=top, 1=bottom
            let left = cFracs[c] * iw, right = cFracs[c + 1] * iw
            let top = rFracs[r] * ih, bottom = rFracs[r + 1] * ih
            let srcW = right - left, srcH = bottom - top
            let srcRect = NSRect(x: left, y: ih - bottom, width: srcW, height: srcH)
            let card = NSView(frame: NSRect(x: x, y: 0, width: 56, height: 66))
            let cv = NSImageView(frame: NSRect(x: 0, y: 14, width: 56, height: 44))
            cv.imageScaling = .scaleProportionallyUpOrDown
            if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: srcRect) {
                cv.image = NSImage(cgImage: cgImg, size: srcRect.size)
            }
            card.addSubview(cv)
            let lb = NSTextField(frame: NSRect(x: 0, y: 0, width: 56, height: 12))
            lb.stringValue = String(i + 1); lb.alignment = .center
            lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = .systemFont(ofSize: 9); lb.textColor = .secondaryLabelColor; card.addSubview(lb)
            thumbStrip.addSubview(card); x += 60
        }
    }

    @objc func uploadSpritesheet() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType.png]; p.allowsMultipleSelection = false
        p.begin { [weak self] r in
            guard r == .OK, let u = p.url, let s = self, let img = NSImage(contentsOf: u) else { return }
            let dest = NSHomeDirectory() + "/.workbuddy/duck-custom/spritesheet.png"
            try? FileManager.default.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: dest)
            try? FileManager.default.copyItem(at: u, to: URL(fileURLWithPath: dest))
            s.currentSpritesheetPath = dest; s.previewView.image = img; s.updateFrameThumbnails()
            s.statusLabel.stringValue = "Spritesheet loaded. Adjust grid \u{2192} Convert \u{2192} Apply."
        }
    }

    @objc func generateSpritesheet() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { statusLabel.stringValue = "Enter a description first."; return }
        statusLabel.stringValue = "Generating (30-60s)..."; genButton.isEnabled = false; spinner.startAnimation(nil)
        let sp = scriptsDir() + "pet-generate-character.py"
        let rows = rowsField.stringValue.isEmpty ? "1" : rowsField.stringValue
        let cols = colsField.stringValue.isEmpty ? "5" : colsField.stringValue
        DispatchQueue.global().async {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            t.arguments = [sp, prompt, "--rows", rows, "--cols", cols,
                          "--canvas-size", String(Int(self.canvasSlider.doubleValue)),
                          "--frame-delay", String(Int(self.delaySlider.doubleValue))]
            let p = Pipe(); let ep = Pipe(); t.standardOutput = p; t.standardError = ep
            do { try t.run(); t.waitUntilExit() } catch {
                DispatchQueue.main.async { self.statusLabel.stringValue = "Failed"; self.genButton.isEnabled = true; self.spinner.stopAnimation(nil) }
                return
            }
            let d = p.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: ep.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard !d.isEmpty, let r = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                DispatchQueue.main.async { self.statusLabel.stringValue = "Error: \(err.prefix(100))"; self.genButton.isEnabled = true; self.spinner.stopAnimation(nil) }
                return
            }
            DispatchQueue.main.async {
                self.spinner.stopAnimation(nil); self.genButton.isEnabled = true
                if let e = r["error"] as? String { self.statusLabel.stringValue = "Error: \(e)"; return }
                if let states = r["states"] as? [String: String] {
                    self.generatedStates = states
                    if let pth = r["spritesheet"] as? String { self.currentSpritesheetPath = pth; self.previewView.image = NSImage(contentsOfFile: pth) }
                    self.previewView.resetCustomSplits()
                    self.updateFrameThumbnails(); self.statusLabel.stringValue = "Generated \(states.count) GIFs."
                    self.showAnimationPreview(states)
                }
            }
        }
    }

    @objc func convertToGif() {
        guard !currentSpritesheetPath.isEmpty, FileManager.default.fileExists(atPath: currentSpritesheetPath) else {
            statusLabel.stringValue = "No spritesheet. Generate or Upload first."; return
        }
        statusLabel.stringValue = "Converting..."; spinner.startAnimation(nil)
        let sp = scriptsDir() + "pet-convert-spritesheet.py"
        let rows = rowsField.stringValue.isEmpty ? "1" : rowsField.stringValue
        let cols = colsField.stringValue.isEmpty ? "5" : colsField.stringValue
        let rSplits = previewView.rowSplits().map { String(format: "%.4f", $0) }.joined(separator: ",")
        let cSplits = previewView.colSplits().map { String(format: "%.4f", $0) }.joined(separator: ",")
        DispatchQueue.global().async {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            t.arguments = [sp, self.currentSpritesheetPath, "--rows", rows, "--cols", cols,
                          "--row-splits", rSplits, "--col-splits", cSplits,
                          "--canvas-size", String(Int(self.canvasSlider.doubleValue)),
                          "--frame-delay", String(Int(self.delaySlider.doubleValue))]
            let p = Pipe(); let ep = Pipe(); t.standardOutput = p; t.standardError = ep
            do { try t.run(); t.waitUntilExit() } catch {
                DispatchQueue.main.async { self.statusLabel.stringValue = "Convert failed"; self.spinner.stopAnimation(nil) }
                return
            }
            let d = p.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: ep.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard !d.isEmpty, let r = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                DispatchQueue.main.async { self.statusLabel.stringValue = "Error: \(err.prefix(80))"; self.spinner.stopAnimation(nil) }
                return
            }
            DispatchQueue.main.async {
                self.spinner.stopAnimation(nil)
                if let e = r["error"] as? String { self.statusLabel.stringValue = "Error: \(e)"; return }
                if let states = r["states"] as? [String: String] {
                    self.generatedStates = states; self.statusLabel.stringValue = "Converted \(states.count) animations."
                    self.showAnimationPreview(states)
                }
            }
        }
    }

    @objc func applyToPet() {
        guard !generatedStates.isEmpty else { statusLabel.stringValue = "Convert first."; return }
        let key = generatedStates.keys.sorted().first!
        let path = generatedStates[key]!
        let resDir = scriptsDir()
        let dest = resDir + "duck-idle.gif"
        // Backup original duck before overwriting
        let backup = dest + ".bak"
        if !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.copyItem(atPath: dest, toPath: backup)
        }
        try? FileManager.default.removeItem(atPath: dest)
        try? FileManager.default.copyItem(atPath: path, toPath: dest)
        cfg.idleGifPath = dest; cfg.petType = "custom"; cfg.save()
        if let duck = AppDelegate.instance?.duck { duck.reloadGIFs() }
        let sd = NSHomeDirectory() + "/.workbuddy/duck-sprites/"
        try? FileManager.default.createDirectory(atPath: sd, withIntermediateDirectories: true)
        for (n, p) in generatedStates {
            try? FileManager.default.removeItem(atPath: sd + n + ".gif")
            try? FileManager.default.copyItem(atPath: p, toPath: sd + n + ".gif")
        }
        statusLabel.stringValue = "Applied \(generatedStates.count) animations."
    }

    @objc func resetToDuck() {
        let resDir = scriptsDir()
        let backupPath = resDir + "duck-idle.gif.bak"
        let destPath = resDir + "duck-idle.gif"
        if FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.removeItem(atPath: destPath)
            try? FileManager.default.copyItem(atPath: backupPath, toPath: destPath)
        }
        cfg.idleGifPath = ""; cfg.petType = "duck"; cfg.save()
        if let duck = AppDelegate.instance?.duck { duck.reloadGIFs() }
        statusLabel.stringValue = "Reset to Duck."
    }

    @objc func resetToCapybara() {
        cfg.idleGifPath = ""; cfg.petType = "capybara"; cfg.save()
        if let duck = AppDelegate.instance?.duck { duck.reloadGIFs() }
        statusLabel.stringValue = "Reset to Capybara."
    }

    @objc func resetGridLines() {
        previewView.resetCustomSplits()
        updateFrameThumbnails()
        statusLabel.stringValue = "Grid reset to equal division."
    }

    func showAnimationPreview(_ states: [String: String]) {
        guard let animStrip = animScrollView?.documentView else { return }
        // Clear existing previews (keep the label)
        animStrip.subviews.forEach { if $0.tag != 9001 { $0.removeFromSuperview() } }
        if let label = animStrip.viewWithTag(9001) as? NSTextField { label.isHidden = true }

        var x: CGFloat = 10; let sortedKeys = states.keys.sorted()
        for key in sortedKeys {
            guard let gifPath = states[key] else { continue }
            let card = NSView(frame: NSRect(x: x, y: 0, width: 190, height: 200))
            let gv = NSImageView(frame: NSRect(x: 8, y: 26, width: 174, height: 170))
            gv.imageScaling = .scaleProportionallyUpOrDown
            gv.animates = true
            if let gifImg = NSImage(contentsOfFile: gifPath) { gv.image = gifImg }
            card.addSubview(gv)
            let lb = NSTextField(frame: NSRect(x: 2, y: 2, width: 126, height: 18))
            lb.stringValue = key; lb.alignment = .center
            lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = .systemFont(ofSize: 9); lb.textColor = .secondaryLabelColor; card.addSubview(lb)
            animStrip.addSubview(card)
            x += 140
        }
        animStrip.frame.size.width = max(animScrollView.frame.width, x + 10)
        animScrollView.documentView = animStrip
    }

    private var body: NSView? { window?.contentView?.subviews.first(where: { $0 is NSScrollView })?.subviews.first }

    override func showWindow(_ s: Any?) {
        window?.center(); super.showWindow(s)
        // Wait for window to finish layout, then scroll to top
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let sv = self.window?.contentView?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
                  let doc = sv.documentView else { return }
            var b = sv.contentView.bounds
            b.origin.y = max(0, doc.frame.height - b.height)
            sv.contentView.bounds = b
        }
    }
}


class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    var scaleSlider:NSSlider!, scaleLabel:NSTextField!
    var bubbleWidthSlider:NSSlider!, bwLabel:NSTextField!
    var bubbleHeightSlider:NSSlider!, bhLabel:NSTextField!
    var maxVisibleSlider:NSSlider!, mvLabel:NSTextField!
    var timeoutSlider:NSSlider!, timeoutLabel:NSTextField!
    var topToggle:NSButton!, agentSyncToggle:NSButton!
    var ctxSlider:NSSlider!, ctxLabel:NSTextField!
    var compSlider:NSSlider!, compLabel:NSTextField!
    var llmKey:NSSecureTextField!, llmModel:NSTextField!, llmUrl:NSTextField!
    var idleLabel:NSTextField!, walkLabel:NSTextField!
    var histPath:NSTextField!
    var journalTemplatePopup:NSPopUpButton!, journalPromptView:NSTextView!
    var onApply:(()->Void)?
    var genPreview: NSImageView!, genStatus: NSTextField!, genSpinner: NSProgressIndicator!
    var genPrompt: NSTextField!, genButton: NSButton!

    convenience init() {
        let w:CGFloat = 460, h:CGFloat = 850
        let win = NSWindow(contentRect:NSRect(x:0,y:0,width:w,height:h),
            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        win.title = "Desktop Duck · Preferences"; win.isReleasedWhenClosed = false
        win.minSize = NSSize(width:420,height:650); win.center()
        self.init(window:win); buildUI(NSSize(width:w,height:h))
    }

    func buildUI(_ sz:NSSize) {
        guard let win = window else { return }
        let w = sz.width
        let sv = NSScrollView(frame:NSRect(x:0,y:0,width:w,height:sz.height))
        sv.drawsBackground = false; sv.hasVerticalScroller = true; sv.borderType  = .noBorder; sv.autohidesScrollers = true
        let m:CGFloat = 24; let body = NSView(frame:NSRect(x:0,y:0,width:w,height:1800)); var y:CGFloat = 1780

        @discardableResult func sec(_ t:String)->NSTextField {
            let lb = NSTextField(frame:NSRect(x:m,y:y-20,width:w-m*2,height:20))
            lb.stringValue = t; lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = NSFont.boldSystemFont(ofSize:13); lb.textColor = .labelColor; y -= 32; body.addSubview(lb); return lb
        }
        func mkSlider(min:Double,max:Double,cur:Double,tag:Int)->(NSSlider,NSTextField) {
            let sl = NSSlider(frame:NSRect(x:m,y:y-18,width:w-m*2-60,height:20))
            sl.minValue = min; sl.maxValue = max; sl.doubleValue = cur; sl.tag = tag; sl.target = self; sl.action = #selector(sliderChanged)
            let lb = NSTextField(frame:NSRect(x:w-m-55,y:y-18,width:55,height:20))
            lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = NSFont.monospacedDigitSystemFont(ofSize:12,weight:.regular); lb.alignment = .right; lb.textColor = .secondaryLabelColor
            y -= 26; body.addSubview(sl); body.addSubview(lb); return (sl,lb)
        }
        func mkSub(_ t:String) {
            let lb = NSTextField(frame:NSRect(x:m,y:y-14,width:w-m*2,height:14))
            lb.stringValue = t; lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font = .systemFont(ofSize:10); lb.textColor = .secondaryLabelColor; y -= 18; body.addSubview(lb)
        }

        // Appearance
        sec("Appearance")
        mkSub("Pet Size"); (scaleSlider,scaleLabel) = mkSlider(min:1,max:8,cur:Double(cfg.scale),tag:1)
        mkSub("Window Level")
        let levelPopup = NSPopUpButton(frame:NSRect(x:m,y:y-22,width:200,height:22),pullsDown:false)
        levelPopup.addItems(withTitles:["Always at Bottom","Normal","Always on Top"])
        levelPopup.selectItem(at: cfg.windowLevel)
        levelPopup.target = self; levelPopup.action = #selector(levelChanged)
        y -= 28; body.addSubview(levelPopup)
        let gifH = NSFont.systemFont(ofSize:11)
        idleLabel = NSTextField(frame:NSRect(x:m,y:y-18,width:w-m*2,height:18)); idleLabel.isBezeled = false; idleLabel.drawsBackground = false
        idleLabel.isEditable = false; idleLabel.font = gifH; idleLabel.textColor = .secondaryLabelColor
        idleLabel.stringValue = cfg.idleGifPath.isEmpty ? "Idle GIF: default" : "Idle GIF: "+(cfg.idleGifPath as NSString).lastPathComponent
        y -= 16; body.addSubview(idleLabel)
        let idleBtn = NSButton(frame:NSRect(x:m,y:y-20,width:140,height:20))
        idleBtn.title = "Choose Custom GIF..."; idleBtn.bezelStyle = .inline; idleBtn.font = .systemFont(ofSize:11)
        idleBtn.target = self; idleBtn.action = #selector(chooseIdle); y -= 28; body.addSubview(idleBtn)

        mkSub("Default Pet")
        let petRow = NSView(frame: NSRect(x: m, y: y - 28, width: w - m * 2, height: 28))
        let duckBtn = NSButton(frame: NSRect(x: 0, y: 2, width: 80, height: 24))
        duckBtn.title = "\u{1F986} Duck"; duckBtn.bezelStyle = .rounded; duckBtn.font = .systemFont(ofSize: 11)
        duckBtn.target = self; duckBtn.action = #selector(switchToDuck); petRow.addSubview(duckBtn)
        let capyBtn = NSButton(frame: NSRect(x: 88, y: 2, width: 100, height: 24))
        capyBtn.title = "\u{1F9AB} Capybara"; capyBtn.bezelStyle = .rounded; capyBtn.font = .systemFont(ofSize: 11)
        capyBtn.target = self; capyBtn.action = #selector(switchToCapybara); petRow.addSubview(capyBtn)
        let petStatus = NSTextField(frame: NSRect(x: 200, y: 6, width: 120, height: 16))
        petStatus.stringValue = cfg.petType == "capybara" ? "Active: Capybara" : "Active: Duck"
        petStatus.isBezeled = false; petStatus.drawsBackground = false; petStatus.isEditable = false
        petStatus.font = .systemFont(ofSize: 10); petStatus.textColor = .secondaryLabelColor
        petStatus.tag = 888; petRow.addSubview(petStatus)
        y -= 36; body.addSubview(petRow)

        // AI Character Generation
        sec("Generate Character Animation")
        let editorBtn = NSButton(frame:NSRect(x:m,y:y-30,width:w-m*2,height:30))
        editorBtn.title = "🎨 Open Spritesheet Editor"
        editorBtn.bezelStyle = .rounded; editorBtn.font = .systemFont(ofSize:13, weight:.medium)
        editorBtn.target = self; editorBtn.action = #selector(openSpritesheetEditor)
        y -= 44; body.addSubview(editorBtn)

        // Names
        sec("Personalization")
        func mkNameField(_ label:String, _ value:String) -> NSTextField {
            mkSub(label)
            let tf = NSTextField(frame:NSRect(x:m,y:y-22,width:w-m*2,height:22))
            tf.stringValue = value; tf.isBezeled = true; tf.bezelStyle = .squareBezel
            tf.font = .systemFont(ofSize:12); tf.delegate = self; y -= 28; body.addSubview(tf); return tf
        }
        let userNameField = mkNameField("Your Name (what AI calls you)", cfg.userName)
        let aiNameField = mkNameField("AI Name (what the pet calls itself)", cfg.aiName)
        userNameField.tag = 100; aiNameField.tag = 101

        // Bubbles
        sec("Bubbles")
        mkSub("Width (px)"); (bubbleWidthSlider,bwLabel) = mkSlider(min:160,max:400,cur:Double(cfg.bubbleWidth),tag:2)
        mkSub("Max Height (px, scrollable)"); (bubbleHeightSlider,bhLabel) = mkSlider(min:80,max:600,cur:Double(cfg.bubbleMaxHeight),tag:3)
        mkSub("Max Visible Bubbles"); (maxVisibleSlider,mvLabel) = mkSlider(min:1,max:10,cur:Double(cfg.maxVisible),tag:4)
        mkSub("Bubble Timeout (seconds, 0 = never)"); (timeoutSlider,timeoutLabel) = mkSlider(min:0,max:300,cur:cfg.bubbleTimeout,tag:7)

        // Chat
        sec("Chat & Memory")
        mkSub("Chat History File")
        histPath = NSTextField(frame:NSRect(x:m,y:y-22,width:w-m*2-60,height:22))
        histPath.stringValue = cfg.chatHistoryPath; histPath.isBezeled = true; histPath.bezelStyle = .squareBezel
        histPath.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular); histPath.delegate = self; y -= 22; body.addSubview(histPath)
        let hb = NSButton(frame:NSRect(x:w-m-56,y:y-6,width:60,height:20))
        hb.title = "Browse..."; hb.bezelStyle = .inline; hb.font = .systemFont(ofSize:10)
        hb.target = self; hb.action = #selector(chooseHistPath); y -= 26; body.addSubview(hb)
        mkSub("Context Window (past turns included)"); (ctxSlider,ctxLabel) = mkSlider(min:0,max:50,cur:Double(cfg.contextWindow),tag:5)
        mkSub("Compress Threshold (turns before summarizing)"); (compSlider,compLabel) = mkSlider(min:5,max:200,cur:Double(cfg.compressThreshold),tag:6)

        // Journal
        sec("Journal & Mindfulness")
        mkSub("Template")
        journalTemplatePopup = NSPopUpButton(frame:NSRect(x:m,y:y-22,width:w-m*2,height:22),pullsDown:false)
        for (name,_) in JOURNAL_TEMPLATES { journalTemplatePopup.addItem(withTitle:name) }
        journalTemplatePopup.addItem(withTitle:"✏️ Custom")
        journalTemplatePopup.selectItem(withTitle:cfg.journalTemplate)
        journalTemplatePopup.target = self; journalTemplatePopup.action = #selector(templateChanged)
        y -= 28; body.addSubview(journalTemplatePopup)

        mkSub("Prompt" + (cfg.journalTemplate == "✏️ Custom" ? " (editable)" : " (read-only)"))
        let pv = NSScrollView(frame:NSRect(x:m,y:y-70,width:w-m*2,height:66))
        pv.hasVerticalScroller = true; pv.borderType = .bezelBorder; y -= 74; body.addSubview(pv)
        journalPromptView = NSTextView(frame:NSRect(x:0,y:0,width:w-m*2-16,height:66))
        journalPromptView.string = cfg.journalPrompt; journalPromptView.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular)
        journalPromptView.isRichText = false; journalPromptView.isEditable = (cfg.journalTemplate == "✏️ Custom")
        journalPromptView.delegate = self; pv.documentView = journalPromptView

        let jvBtn = NSButton(frame:NSRect(x:m,y:y-24,width:160,height:24))
        jvBtn.title = "View Journal"; jvBtn.bezelStyle = .rounded; jvBtn.target = self; jvBtn.action = #selector(viewJournal)
        y -= 30; body.addSubview(jvBtn)

        // LLM
        sec("AI Model")
        func mkTF(_ label:String)->NSTextField {
            let lb = NSTextField(frame:NSRect(x:m,y:y-14,width:w-m*2,height:14)); lb.stringValue = label
            lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false; lb.font = .systemFont(ofSize:10)
            lb.textColor = .secondaryLabelColor; y -= 18; body.addSubview(lb)
            let tf = NSTextField(frame:NSRect(x:m,y:y-22,width:w-m*2,height:22))
            tf.isBezeled = true; tf.bezelStyle = .squareBezel; tf.delegate = self
            tf.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular); y -= 28; body.addSubview(tf); return tf
        }
        mkSub("API Key (auto-saved)")
        llmKey = NSSecureTextField(frame:NSRect(x:m,y:y-22,width:w-m*2,height:22))
        llmKey.stringValue = cfg.llmApiKey; llmKey.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular)
        llmKey.delegate = self; y -= 28; body.addSubview(llmKey)
        llmModel = mkTF("Model Name"); llmModel.stringValue = cfg.llmModel
        llmUrl = mkTF("API Endpoint URL"); llmUrl.stringValue = cfg.llmUrl

        let saveAI = NSButton(frame: NSRect(x: m, y: y - 28, width: w - m * 2, height: 26))
        saveAI.title = "Save AI Config"; saveAI.bezelStyle = .rounded; saveAI.font = .systemFont(ofSize: 11, weight: .medium)
        saveAI.target = self; saveAI.action = #selector(saveAIConfig); y -= 36; body.addSubview(saveAI)

        // Agent
        sec("Agent Integration")
        agentSyncToggle = NSButton(checkboxWithTitle:"Sync WorkBuddy thoughts to Duck",target:self,action:#selector(agentToggled))
        agentSyncToggle.frame = NSRect(x:m-2,y:y-22,width:400,height:22); agentSyncToggle.state = cfg.agentSync ? .on:.off; y -= 30; body.addSubview(agentSyncToggle)

        // Data
        sec("Data")
        let clearBtn = NSButton(frame:NSRect(x:m,y:y-26,width:180,height:26))
        clearBtn.title = "Clear Chat History"; clearBtn.bezelStyle = .rounded; clearBtn.target = self; clearBtn.action = #selector(clearHist)
        y -= 34; body.addSubview(clearBtn)
        let resetBtn = NSButton(frame:NSRect(x:m,y:y-26,width:180,height:26))
        resetBtn.title = "Reset All Settings"; resetBtn.bezelStyle = .rounded; resetBtn.target = self; resetBtn.action = #selector(resetDef)
        y -= 34; body.addSubview(resetBtn)

        // About
        sec("About")
        let aboutL = NSTextField(frame:NSRect(x:m,y:y-28,width:w-m*2,height:32))
        aboutL.stringValue = "Desktop Duck Pet v1.1\nRight-click -> Preferences | Menu bar -> All settings"
        aboutL.isBezeled = false; aboutL.drawsBackground = false; aboutL.isEditable = false
        aboutL.font = .systemFont(ofSize:10); aboutL.textColor = .secondaryLabelColor; aboutL.lineBreakMode = .byWordWrapping; body.addSubview(aboutL)

        sv.documentView = body; win.contentView = sv; updateLabels()
    }

    override func showWindow(_ s: Any?) {
        window?.center(); super.showWindow(s); NSApp.activate(ignoringOtherApps:true)
        // Scroll to top — macOS coordinate system originates bottom-left
        DispatchQueue.main.async {
            if let sv = self.window?.contentView as? NSScrollView, let doc = sv.documentView {
                doc.scroll(NSPoint(x: 0, y: doc.bounds.height))
            }
        }
    }

    @objc func sliderChanged(_:NSSlider) { updateLabels(); applyConfig() }
    @objc func levelChanged(_ sender: NSPopUpButton) {
        cfg.windowLevel = sender.indexOfSelectedItem
        cfg.save(); onApply?()
    }
    @objc func agentToggled(_ s:NSButton) { cfg.agentSync = (s.state == .on); cfg.save() }

    @objc func saveAIConfig() {
        cfg.llmApiKey = llmKey.stringValue
        cfg.llmModel = llmModel.stringValue
        cfg.llmUrl = llmUrl.stringValue
        cfg.save()
    }

    @objc func switchToDuck() {
        let resDir = scriptsDir()
        let backupPath = resDir + "duck-idle.gif.bak"
        let destPath = resDir + "duck-idle.gif"
        // Restore original duck from backup if available
        if FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.removeItem(atPath: destPath)
            try? FileManager.default.copyItem(atPath: backupPath, toPath: destPath)
        }
        cfg.idleGifPath = ""; cfg.petType = "duck"; cfg.save()
        idleLabel.stringValue = "Idle GIF: default"
        if let s = window?.contentView?.viewWithTag(888) as? NSTextField { s.stringValue = "Active: Duck" }
        if let duck = AppDelegate.instance?.duck { duck.reloadGIFs() }
    }
    @objc func switchToCapybara() {
        cfg.idleGifPath = ""; cfg.petType = "capybara"; cfg.save()
        idleLabel.stringValue = "Idle GIF: default"
        if let s = window?.contentView?.viewWithTag(888) as? NSTextField { s.stringValue = "Active: Capybara" }
        if let duck = AppDelegate.instance?.duck { duck.reloadGIFs() }
    }

    @objc func chooseIdle() { pickGif{self.idleLabel.stringValue = "Idle GIF: "+($0 as NSString).lastPathComponent} }
    func pickGif(_ cb:@escaping(String)->Void) {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType.gif]; p.allowsMultipleSelection = false
        p.canChooseFiles = true; p.canChooseDirectories = false
        p.begin{r in guard r == .OK,let u = p.url else{return};let pa = u.path;cb(pa)
            cfg.idleGifPath = pa; cfg.save()}
    }

    // ── AI Character Generation ─────────────────────────────
    var genIdlePath: String = ""
    let genOutputDir = NSHomeDirectory() + "/.workbuddy/duck-custom/"
    var genScriptPath: String {
        let exe = CommandLine.arguments[0]
        let binDir = (exe as NSString).deletingLastPathComponent
        let resDir = binDir + "/../Resources/"
        let sp = resDir + "pet-generate-character.py"
        if FileManager.default.fileExists(atPath: sp) { return sp }
        return binDir + "/pet-generate-character.py"
    }

    @objc func generateCharacter() {
        let prompt = genPrompt.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            genStatus.stringValue = "Please enter a description first."
            return
        }
        genStatus.stringValue = "Generating character image..."
        genSpinner.startAnimation(nil)
        genButton.isEnabled = false

        DispatchQueue.global().async {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            t.arguments = [self.genScriptPath, prompt, "--output-dir", self.genOutputDir]
            let outPipe = Pipe(); t.standardOutput = outPipe; t.standardError = Pipe()
            do { try t.run(); t.waitUntilExit() } catch {
                DispatchQueue.main.async {
                    self.genStatus.stringValue = "Failed to run generator: \(error.localizedDescription)"
                    self.genSpinner.stopAnimation(nil); self.genButton.isEnabled = true
                }
                return
            }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let _ = String(data: data, encoding: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    self.genStatus.stringValue = "Failed to parse generator output."
                    self.genSpinner.stopAnimation(nil); self.genButton.isEnabled = true
                }
                return
            }
            DispatchQueue.main.async {
                if let err = result["error"] as? String {
                    self.genStatus.stringValue = "Error: \(err)"
                } else if let idlePath = result["idle"] as? String {
                    self.genIdlePath = idlePath
                    if let img = NSImage(contentsOfFile: idlePath) {
                        self.genPreview.image = img
                    }
                    self.genStatus.stringValue = "Generated! Click Apply to use."
                    self.idleLabel.stringValue = "Idle GIF: idle.gif (custom)"
                } else {
                    self.genStatus.stringValue = "Unexpected response from generator."
                }
                self.genSpinner.stopAnimation(nil)
                self.genButton.isEnabled = true
            }
        }
    }
    @objc func applyGenIdle() {
        guard !genIdlePath.isEmpty else { genStatus.stringValue = "Generate a character first."; return }
        applyGenGif(genIdlePath)
        genStatus.stringValue = "Character applied!"
    }
    func applyGenGif(_ srcPath: String) {
        let resDir = scriptsDir()
        let destPath = resDir + "duck-idle.gif"
        let backupPath = destPath + ".bak"
        if !FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.copyItem(atPath: destPath, toPath: backupPath)
        }
        try? FileManager.default.removeItem(atPath: destPath)
        try? FileManager.default.copyItem(atPath: srcPath, toPath: destPath)
        cfg.idleGifPath = destPath
        idleLabel.stringValue = "Idle GIF: duck-idle.gif (custom)"
        cfg.save()
        if let duck = AppDelegate.instance?.duck {
            duck.reloadGIFs()
            duck.receiveThought(text: "\u{1F5BC}\u{FE0F} New look applied!", type: "done")
        }
    }
    @objc func restoreDefaultDuck() {
        let resDir = scriptsDir()
        let backupPath = resDir + "duck-idle.gif.bak"
        let destPath = resDir + "duck-idle.gif"
        if FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.removeItem(atPath: destPath)
            try? FileManager.default.copyItem(atPath: backupPath, toPath: destPath)
        }
        cfg.idleGifPath = ""
        cfg.petType = "duck"
        cfg.save()
        idleLabel.stringValue = "Idle GIF: default"
        genPreview.image = nil
        genIdlePath = ""
        genStatus.stringValue = "Restored default duck!"
        if let duck = AppDelegate.instance?.duck {
            duck.reloadGIFs()
        }
    }

    @objc func chooseHistPath() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.allowsMultipleSelection = false; p.canCreateDirectories = true
        p.begin{r in guard r == .OK,let u = p.url else{return}
            let f = u.path+"/chat-history.json"; self.histPath.stringValue = f; cfg.chatHistoryPath = f; cfg.save()}
    }

    @objc func clearHist() {
        let a = NSAlert(); a.messageText = "Clear Chat History"
        a.informativeText = "This will delete all bubble records and chat history."; a.addButton(withTitle:"Clear"); a.addButton(withTitle:"Cancel")
        a.alertStyle = .warning; if a.runModal() == .alertFirstButtonReturn {
            if let duck = AppDelegate.instance?.duck {
                for b in duck.bubbles { b.win.orderOut(nil); b.timer?.invalidate() }
                duck.bubbles.removeAll(); duck.stackTimer?.invalidate(); duck.stackTimer = nil
                duck.dismissFold()
                duck.receiveThought(text:"Chat history cleared.", type:"done")
            }
            if let app = AppDelegate.instance { app.cnt = 0 }
            cfg.clearHistory()
        }
    }

    @objc func viewJournal() { AppDelegate.instance?.showJournal() }
    @objc func openSpritesheetEditor() { AppDelegate.instance?.showSpritesheetEditor() }

    @objc func templateChanged() {
        let selected = journalTemplatePopup.titleOfSelectedItem ?? "✏️ Custom"
        cfg.journalTemplate = selected
        if selected == "✏️ Custom" {
            journalPromptView.isEditable = true
            // Keep current custom prompt
        } else {
            journalPromptView.isEditable = false
            // Load template prompt
            for (name, prompt) in JOURNAL_TEMPLATES {
                if name == selected { journalPromptView.string = prompt; cfg.journalPrompt = prompt; break }
            }
        }
        cfg.save()
    }

    @objc func resetDef() {
        cfg.scale = 2.0; cfg.windowLevel = 2; cfg.idleGifPath = ""; cfg.walkGifPath = ""
        cfg.bubbleWidth = 240; cfg.bubbleMaxHeight = 200; cfg.maxVisible = 3; cfg.bubbleTimeout = 0
        cfg.contextWindow = 10; cfg.compressThreshold = 20; cfg.agentSync = true
        cfg.journalTemplate = "🧭 Odyssey Plan"
        cfg.journalPrompt = JOURNAL_TEMPLATES[0].1
        cfg.save(); applyConfig()
        scaleSlider.doubleValue = 2.0; bubbleWidthSlider.doubleValue = 240; bubbleHeightSlider.doubleValue = 200
        maxVisibleSlider.doubleValue = 3; timeoutSlider.doubleValue = 0
        ctxSlider.doubleValue = 10; compSlider.doubleValue = 20; topToggle.state = .on; agentSyncToggle.state = .on
        idleLabel.stringValue = "Idle GIF: default"; walkLabel.stringValue = "Walk GIF: default"
        histPath.stringValue = cfg.chatHistoryPath
        journalTemplatePopup.selectItem(withTitle:"🧭 Odyssey Plan")
        journalPromptView.string = cfg.journalPrompt; journalPromptView.isEditable = false
        updateLabels(); onApply?()
    }

    func updateLabels() {
        scaleLabel.stringValue = String(format:"%.1fx",scaleSlider.doubleValue)
        bwLabel.stringValue = "\(Int(bubbleWidthSlider.doubleValue))px"
        bhLabel.stringValue = "\(Int(bubbleHeightSlider.doubleValue))px"
        mvLabel.stringValue = "\(Int(maxVisibleSlider.doubleValue))"
        timeoutLabel.stringValue = timeoutSlider.doubleValue == 0 ? "never" : "\(Int(timeoutSlider.doubleValue))s"
        ctxLabel.stringValue = "\(Int(ctxSlider.doubleValue))"
        compLabel.stringValue = "\(Int(compSlider.doubleValue))"
    }

    func applyConfig() {
        cfg.scale = CGFloat(scaleSlider.doubleValue); cfg.bubbleWidth = CGFloat(bubbleWidthSlider.doubleValue)
        cfg.bubbleMaxHeight = CGFloat(bubbleHeightSlider.doubleValue); cfg.maxVisible = Int(maxVisibleSlider.doubleValue)
        cfg.bubbleTimeout = timeoutSlider.doubleValue; cfg.contextWindow = Int(ctxSlider.doubleValue)
        cfg.compressThreshold = Int(compSlider.doubleValue); cfg.llmApiKey = llmKey.stringValue
        cfg.llmModel = llmModel.stringValue; cfg.llmUrl = llmUrl.stringValue; cfg.chatHistoryPath = histPath.stringValue
        cfg.journalPrompt = journalPromptView.string; cfg.save(); onApply?()
    }

    func controlTextDidChange(_ obj:Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        if tf===llmKey {cfg.llmApiKey = tf.stringValue}else if tf===llmModel{cfg.llmModel = tf.stringValue}
        else if tf===llmUrl{cfg.llmUrl = tf.stringValue}else if tf===histPath{cfg.chatHistoryPath = tf.stringValue}
        else if tf.tag == 100 {cfg.userName = tf.stringValue}else if tf.tag == 101 {cfg.aiName = tf.stringValue}
        cfg.save()
    }
}

extension SettingsWindowController: NSTextViewDelegate {
    func textDidChange(_ n:Notification) {
        if let tv = n.object as? NSTextView, tv===journalPromptView { cfg.journalPrompt = tv.string; cfg.save() }
    }
}

// ─── DuckView ──────────────────────────────────────────────
class DuckView: NSView, NSTextViewDelegate {
    var img:NSImageView!; var idleGIF:NSImage?, walkGIF:NSImage?
    struct BubbleEntry { var win:NSWindow; var view:BubbleView; var btn:ButtonOverlay; var timer:Timer? }
    var bubbles:[BubbleEntry] = []; var foldWin:NSWindow?; var foldView:FoldView?
    var isExpanded = false; var stackTimer:Timer?
    var inputWin:NSWindow?; var inputView:NSTextView?; var replyContext:String?
    var permWin:NSWindow?; var permView:PermView?; var _pendingActionId:String?; var permT:Timer?
    var journalMode = false
    var journalTranscript: [[String:String]] = []
    var faceRight = true,pokeCount = 0,wasDrag = false; var isResizing = false,rs = NSPoint.zero,rsz = NSSize.zero
    var isPoking = false,poffY:CGFloat = 0; var floatEmojis:[(String,CGFloat,CGFloat,CGFloat)] = []
    var lastClickTime:Date = Date.distantPast

    override init(frame:NSRect) { super.init(frame:frame); setup() }
    required init?(coder:NSCoder) { super.init(coder:coder); setup() }

    func setup() {
        reloadGIFs()
        img = NSImageView(frame:bounds); img.wantsLayer = true; img.imageScaling = .scaleProportionallyUpOrDown
        img.animates = true; img.image = idleGIF; img.layer?.minificationFilter = .nearest; img.layer?.magnificationFilter = .nearest
        img.layer?.shadowColor = NSColor.white.cgColor; img.layer?.shadowRadius = 8; img.layer?.shadowOpacity = 0.5; addSubview(img)
    }

    func reloadGIFs() {
        let dir = scriptsDir()
        let defaultName = cfg.petType == "capybara" ? "capybara.gif" : "duck-idle.gif"
        idleGIF = NSImage(contentsOfFile: cfg.idleGifPath.isEmpty ? dir + defaultName : cfg.idleGifPath)
        img?.image = idleGIF
    }

    override func draw(_ d:NSRect) {
        super.draw(d); img.frame = NSRect(x:0,y:poffY,width:bounds.width,height:bounds.height)
        for p in floatEmojis { NSAttributedString(string:p.0,attributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor(white:0,alpha:p.3)]).draw(at:NSPoint(x:bounds.width/2+p.1,y:bounds.height/2+p.2)) }
        let c = NSGraphicsContext.current?.cgContext; c?.setFillColor(red:0,green:0,blue:0,alpha:0.15); c?.beginPath()
        c?.move(to:CGPoint(x:bounds.width,y:0)); c?.addLine(to:CGPoint(x:bounds.width,y:12))
        c?.addLine(to:CGPoint(x:bounds.width-12,y:0)); c?.closePath(); c?.fillPath()
    }

    func pushBubble(text:String,type:String) {
        guard window != nil else { return }
        let fullH = calcBubbleContentHeight(text); let bh = min(fullH,MAX_BUBBLE_HEIGHT); let needsScroll = fullH>MAX_BUBBLE_HEIGHT
        let bw = BUBBLE_WIDTH; let win = makeBubbleWin(x:0,y:0,w:bw,h:bh)
        let bv = BubbleView(frame:NSRect(x:0,y:0,width:bw,height:needsScroll ? fullH:bh)); bv.text = text; bv.btype = type
        let bo = ButtonOverlay(frame:NSRect(x:0,y:0,width:bw,height:bh)); bo.wantsLayer = true; bo.layer?.backgroundColor = NSColor.clear.cgColor
        bo.onClose = {[weak self] in self?.removeBubble(win)}; bo.onReply = {[weak self] in self?.showTextInput(context:text)}
        let container = NSView(frame:NSRect(x:0,y:0,width:bw,height:bh))
        if needsScroll { let sv = NSScrollView(frame:NSRect(x:0,y:0,width:bw,height:bh)); sv.hasVerticalScroller = true
            sv.autohidesScrollers = false; sv.drawsBackground = false; sv.borderType  = .noBorder
            sv.wantsLayer = true; sv.layer?.masksToBounds = true; bv.wantsLayer = true; sv.documentView = bv; container.addSubview(sv) }
        else { container.addSubview(bv) }
        container.addSubview(bo); win.contentView = container; win.orderFront(nil)
        var bt:Timer? = nil
        if cfg.bubbleTimeout > 0 {
            bt = Timer.scheduledTimer(withTimeInterval:cfg.bubbleTimeout,repeats:false) {[weak self] _ in self?.removeBubble(win)}
        }
        bubbles.append(BubbleEntry(win:win,view:bv,btn:bo,timer:bt))
        layoutStack(); startStackTimer()
    }

    func startStackTimer() { guard stackTimer  == nil else{return}; stackTimer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self]_ in self?.layoutStack()} }

    func removeBubble(_ win:NSWindow) {
        guard let idx = bubbles.firstIndex(where:{$0.win===win}) else{return}
        bubbles[idx].timer?.invalidate()
        var a:CGFloat = 1
        Timer.scheduledTimer(withTimeInterval:0.04,repeats:true){[weak self] t in guard let self = self else{t.invalidate();return}
            a -= 0.06; win.alphaValue = a; if a<=0{win.orderOut(nil);t.invalidate()
            self.bubbles.removeAll(where:{$0.win===win});self.layoutStack()
            if self.bubbles.isEmpty{self.stackTimer?.invalidate();self.stackTimer = nil}}
        }
    }

    func layoutStack() {
        guard let p = window else{return}; let f = p.frame; let bw = BUBBLE_WIDTH; let cx = f.origin.x+f.width/2-bw/2; var y = f.maxY+4
        let mv = MAX_VISIBLE; let needFold = !isExpanded && bubbles.count>mv
        let start = isExpanded ? 0:max(0,bubbles.count-mv)
        if needFold{ensureFold(cx:cx,y:y,hidden:bubbles.count-mv);y += 22+BUBBLE_GAP}else{dismissFold()}
        for i in start..<bubbles.count { let w = bubbles[i].win; w.setFrameOrigin(NSPoint(x:cx,y:y)); w.orderFront(nil); y += w.frame.height+BUBBLE_GAP }
        for i in 0..<min(start,bubbles.count) { bubbles[i].win.orderOut(nil) }
        if let pw = permWin,_pendingActionId != nil { var ty = f.maxY+4; if needFold{ty += 22+BUBBLE_GAP}
            for i in start..<bubbles.count{ty += bubbles[i].win.frame.height+BUBBLE_GAP}; pw.setFrameOrigin(NSPoint(x:f.origin.x+f.width/2-pw.frame.width/2,y:ty))}
        if let iw = inputWin { var ty = f.maxY+4; if needFold{ty += 22+BUBBLE_GAP}
            for i in start..<bubbles.count{ty += bubbles[i].win.frame.height+BUBBLE_GAP}
            if permWin != nil && _pendingActionId != nil {ty += 68+BUBBLE_GAP}; iw.setFrameOrigin(NSPoint(x:f.origin.x+f.width/2-iw.frame.width/2,y:ty))}
    }

    func ensureFold(cx:CGFloat,y:CGFloat,hidden:Int) {
        if foldWin == nil { foldWin = NSWindow(contentRect:NSRect(x:cx,y:y,width:BUBBLE_WIDTH,height:22),styleMask:.borderless,backing:.buffered,defer:false)
            foldWin!.isOpaque = false; foldWin!.backgroundColor = .clear; foldWin!.level = .floating; foldWin!.hasShadow = false
            foldWin!.ignoresMouseEvents = false; foldWin!.isReleasedWhenClosed = false
            foldView = FoldView(frame:NSRect(x:0,y:0,width:BUBBLE_WIDTH,height:22)); foldView!.onTap = {[weak self] in self?.toggleExpand()}
            foldWin!.contentView = foldView; foldWin!.orderFront(nil) }
        foldView?.text = "▼ \(hidden) more messages..."; foldView?.needsDisplay = true
        foldWin?.setFrameOrigin(NSPoint(x:cx,y:y)); foldWin?.orderFront(nil)
    }

    func toggleExpand() { isExpanded.toggle(); layoutStack() }
    func dismissFold() { foldWin?.orderOut(nil); foldWin = nil; foldView = nil }
    func repositionAll() { layoutStack() }

    func receiveThought(text:String,type:String) {
        if journalMode && (type == "found" || type == "done") {
            journalTranscript.append(["role":"assistant","content":text])
        }
        isPoking = true; var ph = 0
        Timer.scheduledTimer(withTimeInterval:0.06,repeats:true){[weak self]t in guard let self = self else{t.invalidate();return}; ph += 1
            switch ph{case 1...2:self.poffY = CGFloat(ph)*5; case 3...4:self.poffY = CGFloat(4-(ph-2))*5
            case 5:self.poffY = 0;self.isPoking = false;t.invalidate(); default:break}; self.needsDisplay = true}
        pushBubble(text:text,type:type)
        // In journal mode, auto-reopen input so user can continue or click ✕ to end
        if journalMode && (type == "found" || type == "done") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.journalMode, self.inputWin == nil else { return }
                self.showTextInput(context: nil)
            }
        }
    }

    func showPermission(text:String,actionId:String) {
        dismissPerm(response:""); guard let p = window else{return}
        let f = p.frame; let bw:CGFloat = 340,bh:CGFloat = 68; var topY = f.maxY+4
        let nf = !isExpanded && bubbles.count>MAX_VISIBLE; let s = isExpanded ? 0:max(0,bubbles.count-MAX_VISIBLE)
        if nf{topY += 22+BUBBLE_GAP}; for i in s..<bubbles.count{topY += bubbles[i].win.frame.height+BUBBLE_GAP}
        permWin = NSWindow(contentRect:NSRect(x:f.origin.x+f.width/2-bw/2,y:topY,width:bw,height:bh),styleMask:.borderless,backing:.buffered,defer:false)
        permWin!.isOpaque = false; permWin!.backgroundColor = .clear; permWin!.level = .floating; permWin!.hasShadow = false; permWin!.isReleasedWhenClosed = false
        permView = PermView(frame:NSRect(x:0,y:0,width:bw,height:bh)); permView!.text = text
        permView!.onResp = {[weak self] r in self?.dismissPerm(response:r)}; permWin!.contentView = permView; permWin!.orderFront(nil)
        _pendingActionId = actionId; permT = Timer.scheduledTimer(withTimeInterval:30,repeats:false){[weak self]_ in self?.dismissPerm(response:"timeout")}
    }
    func dismissPerm(response:String) {
        guard _pendingActionId != nil else{return}
        if let aid = _pendingActionId,!aid.isEmpty{try?JSONSerialization.data(withJSONObject:["action_id":aid,"response":response]).write(to:URL(fileURLWithPath:RESPONSE_FILE))}
        _pendingActionId = nil; permT?.invalidate(); permWin?.orderOut(nil); permWin = nil; permView = nil
    }

    func fetchRandomContent() {
        let sp = scriptsDir()+"/pet-random-content.py"
        DispatchQueue.global().async{let t = Process();t.executableURL = URL(fileURLWithPath:"/usr/local/bin/python3");t.arguments = [sp];try?t.run()}
    }

    func startJournalSession() {
        // Save any in-progress session before starting a new one
        if journalMode && !journalTranscript.isEmpty {
            saveJournalTranscript()
        }
        journalMode = true; journalTranscript = []
        // Start with the journal prompt as the first message
        let _ = cfg.journalPrompt.prefix(200) + "..."
        pushBubble(text:"Starting journal with \(cfg.journalTemplate)\n\n\(cfg.journalPrompt.prefix(150))...", type:"writing")
        showTextInput(context:nil)
    }

    func endJournalSession() {
        // Save and generate summary
        if !journalTranscript.isEmpty { saveJournalTranscript() }
        journalMode = false
        journalTranscript = []
        pushBubble(text:"📓 Journal saved. View Journal -> Refresh for AI summary.", type:"done")
    }

    func saveJournalTranscript() {
        let df = ISO8601DateFormatter(); df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = df.string(from: Date())
        let tpl = cfg.journalTemplate

        // Load existing journal, handling both old (array) and new (document) formats
        var journal: [String: Any]
        if let d = try? Data(contentsOf: URL(fileURLWithPath: JOURNAL_FILE)),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            journal = j
        } else if let d = try? Data(contentsOf: URL(fileURLWithPath: JOURNAL_FILE)),
                  let oldEntries = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            // Migrate old format to new document model
            var docs: [String: [String: Any]] = [:]
            for entry in oldEntries {
                let name = entry["template"] as? String ?? ""
                if name.isEmpty { continue }
                var doc = docs[name] ?? [
                    "template": name,
                    "content": "",
                    "sessions": [],
                    "created_at": entry["time"] ?? now,
                    "updated_at": entry["time"] ?? now
                ]
                var sessions = doc["sessions"] as? [[String: Any]] ?? []
                sessions.append([
                    "time": entry["time"] ?? now,
                    "transcript": entry["transcript"] ?? [],
                    "processed": false
                ])
                doc["sessions"] = sessions
                docs[name] = doc
            }
            journal = ["documents": docs]
        } else {
            journal = ["documents": [:]]
        }

        // Add new session to the document
        var docs = journal["documents"] as? [String: [String: Any]] ?? [:]
        var doc = docs[tpl] ?? [
            "template": tpl,
            "content": "",
            "sessions": [],
            "created_at": now
        ]
        var sessions = doc["sessions"] as? [[String: Any]] ?? []
        sessions.append([
            "time": now,
            "transcript": journalTranscript,
            "processed": false
        ])
        doc["sessions"] = sessions
        doc["updated_at"] = now
        docs[tpl] = doc
        journal["documents"] = docs

        // Save
        do {
            let data = try JSONSerialization.data(withJSONObject: journal, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: JOURNAL_FILE))
        } catch {
            pushBubble(text: "Failed to save journal: \(error.localizedDescription)", type: "done")
            return
        }

        // Trigger summary generation
        let sp = scriptsDir() + "pet-journal-summary.py"
        if !FileManager.default.fileExists(atPath: sp) {
            pushBubble(text: "Summary script not found", type: "done")
            return
        }
        DispatchQueue.global().async {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            t.arguments = [sp, tpl]
            do { try t.run(); t.waitUntilExit() } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.pushBubble(text: "Summary failed", type: "done")
                }
            }
        }
    }

    func showTextInput(context:String? = nil) {
        dismissInput(); guard let p = window else{return}
        let f = p.frame; let iw:CGFloat = 240,ih:CGFloat = 32; var topY = f.maxY+4
        let nf = !isExpanded && bubbles.count>MAX_VISIBLE; let s = isExpanded ? 0:max(0,bubbles.count-MAX_VISIBLE)
        if nf{topY += 22+BUBBLE_GAP}; for i in s..<bubbles.count{topY += bubbles[i].win.frame.height+BUBBLE_GAP}
        if permWin != nil && _pendingActionId != nil {topY += 68+BUBBLE_GAP}
        inputWin = InputWindow(contentRect:NSRect(x:f.origin.x+f.width/2-iw/2,y:topY,width:iw,height:ih),styleMask:.borderless,backing:.buffered,defer:false)
        inputWin!.isOpaque = false; inputWin!.backgroundColor = .clear; inputWin!.level = .floating; inputWin!.hasShadow = true; inputWin!.isReleasedWhenClosed = false
        // Light translucent background with subtle border
        let bg = NSView(frame:NSRect(x:0,y:0,width:iw,height:ih)); bg.wantsLayer = true; bg.layer?.cornerRadius = 16
        bg.layer?.backgroundColor = NSColor(white:0.97,alpha:0.92).cgColor
        bg.layer?.borderWidth = 0.5; bg.layer?.borderColor = NSColor(white:0.7,alpha:0.5).cgColor
        inputWin!.contentView = bg; replyContext = context
        let tv = ChatTextView(frame:NSRect(x:10,y:4,width:iw-42,height:24))
        tv.font = NSFont(name:"PingFang SC",size:13) ?? .systemFont(ofSize:13); tv.isRichText = false; tv.drawsBackground = false
        tv.isEditable = true; tv.isSelectable = true; tv.focusRingType = .none; tv.delegate = self
        tv.textContainer?.lineFragmentPadding = 0; tv.textContainerInset = NSSize(width:0,height:4)
        tv.textColor = NSColor(white:0.15,alpha:1); tv.insertionPointColor = NSColor(white:0.2,alpha:1)
        tv.string = ""; tv.onSubmit = {[weak self] in self?.submitTextInput()}
        bg.addSubview(tv); inputView = tv
        let phText = journalMode ? "How are you feeling today?" : (context != nil ? "Reply..." : "Chat with duck...")
        let ph = NSTextField(frame:NSRect(x:12,y:6,width:iw-42,height:20)); ph.stringValue = phText
        ph.isBezeled = false; ph.drawsBackground = false; ph.isEditable = false; ph.focusRingType = .none
        ph.font = NSFont(name:"PingFang SC",size:13) ?? .systemFont(ofSize:13); ph.textColor = NSColor(white:0.6,alpha:1); ph.tag = 999; bg.addSubview(ph)
        let cb = NSButton(frame:NSRect(x:iw-28,y:6,width:22,height:20)); cb.title = "✕"; cb.isBordered = false
        cb.font = .systemFont(ofSize:13)
        if journalMode { cb.target = self; cb.action = #selector(closeJournalInput(_:)) }
        else { cb.target = self; cb.action = #selector(cancelOperation(_:)) }
        bg.addSubview(cb)
        inputWin!.orderFront(nil); inputWin!.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true); inputWin!.makeFirstResponder(tv)
    }

    override func cancelOperation(_:Any?) {
        dismissInput()
    }

    @objc func closeJournalInput(_:Any?) {
        endJournalSession()
        dismissInput()
    }

    func textDidChange(_ n:Notification) {
        guard let tv = n.object as? NSTextView,let bg = tv.superview else{return}
        if let ph = bg.viewWithTag(999){ph.isHidden = !tv.string.isEmpty}
    }

    func submitTextInput() {
        guard let tv = inputView else{return}
        let text = tv.string.trimmingCharacters(in:.whitespacesAndNewlines); guard !text.isEmpty else{return}; tv.string = ""
        let ts = DateFormatter(); ts.dateFormat = "yyyy-MM-dd HH:mm:ss"; let now = ts.string(from:Date())
        var entry = "[\(now)] \(text)\n"
        if let ctx = replyContext{entry = "[\(now)] [Reply: \(ctx.prefix(80))...] \(text)\n"}
        if let data = entry.data(using:.utf8) {
            if FileManager.default.fileExists(atPath:INBOX_FILE),let fh = FileHandle(forWritingAtPath:INBOX_FILE){fh.seekToEndOfFile();fh.write(data);fh.closeFile()}
            else{try?data.write(to:URL(fileURLWithPath:INBOX_FILE))}
        }
        appendChatHistory(role:"user",content:text,time:now)
        if journalMode { journalTranscript.append(["role":"user","content":text]) }

        var thoughts:[[String:Any]] = []
        if FileManager.default.fileExists(atPath:THOUGHTS_FILE),let d = try?Data(contentsOf:URL(fileURLWithPath:THOUGHTS_FILE)),
           let t = try?JSONSerialization.jsonObject(with:d) as? [[String:Any]] {thoughts = t}
        thoughts.append(["time":now,"type":"thinking","text":journalMode ? "📓 \(text)" : "💬 \(text)"])
        if let j = try?JSONSerialization.data(withJSONObject:Array(thoughts.suffix(50))),
           let s = String(data:j,encoding:.utf8){try?s.write(toFile:THOUGHTS_FILE,atomically:true,encoding:.utf8)}
        dismissInput()
        let sp = scriptsDir()+"/pet-auto-reply.py"
        DispatchQueue.global().async{let t = Process();t.executableURL = URL(fileURLWithPath:"/usr/local/bin/python3");t.arguments = [sp];try?t.run()}
    }

    func appendChatHistory(role:String,content:String,time:String) {
        var entries:[[String:Any]] = []; let p = cfg.chatHistoryPath
        if FileManager.default.fileExists(atPath:p),let d = try?Data(contentsOf:URL(fileURLWithPath:p)),
           let t = try?JSONSerialization.jsonObject(with:d) as? [[String:Any]] {entries = t}
        entries.append(["role":role,"content":content,"time":time])
        if entries.count>cfg.compressThreshold && cfg.compressThreshold>0 {entries = compressHistory(entries)}
        try?JSONSerialization.data(withJSONObject:entries,options:.prettyPrinted).write(to:URL(fileURLWithPath:p))
    }

    func compressHistory(_ entries:[[String:Any]])->[[String:Any]] {
        let keep = cfg.contextWindow>0 ? cfg.contextWindow:5; let recent = Array(entries.suffix(keep))
        let older = Array(entries.prefix(entries.count-keep)); guard !older.isEmpty else{return recent}
        var s = "Earlier conversation summary: "
        for e in older { let r = e["role"] as? String ?? "?"; let c = e["content"] as? String ?? ""; s += "[\(r)] \(c.prefix(60))... | " }
        return [["role":"system","content":String(s.prefix(500)),"time":"compressed"]]+recent
    }

    func dismissInput() { inputView?.string = ""; inputWin?.orderOut(nil); inputWin = nil; inputView = nil }

    override var acceptsFirstResponder:Bool{true}
    override func mouseDown(with e:NSEvent) {
        let loc = convert(e.locationInWindow,from:nil)
        if loc.x>bounds.width-18 && loc.y<18{isResizing = true;rs = e.locationInWindow;rsz = bounds.size;return}
        wasDrag = false
    }
    override func mouseDragged(with e:NSEvent) {
        if isResizing{let loc = e.locationInWindow; let ns = max(48,min(48*8,max(rsz.width+(loc.x-rs.x),rsz.height-(loc.y-rs.y))))
            guard let w = window else{return}; let f = w.frame
            w.setFrame(NSRect(x:f.origin.x-(ns-f.width)/2,y:f.origin.y-(ns-f.height),width:ns,height:ns),display:true,animate:false)
            img.frame = NSRect(x:0,y:0,width:ns,height:ns);needsDisplay = true;repositionAll();return}
        wasDrag = true; window?.performDrag(with:e);repositionAll()
    }
    override func mouseUp(with e:NSEvent) {
        if isResizing{isResizing = false;saveWindowFrame();return}
        guard !wasDrag else{saveWindowFrame();return}
        let now = Date(); let isDouble = now.timeIntervalSince(lastClickTime)<0.35; lastClickTime = now
        if isDouble { pokeAnimation(); showTextInput(context:nil) }
        else { _ = Timer.scheduledTimer(withTimeInterval:0.35,repeats:false){[weak self]_ in
            guard let self = self,Date().timeIntervalSince(self.lastClickTime)>=0.35 else{return}
            self.pokeAnimation(); self.fetchRandomContent()}}
        saveWindowFrame()
    }

    func pokeAnimation() {
        pokeCount += 1; isPoking = true; poffY = 0; var jp = 0
        Timer.scheduledTimer(withTimeInterval:0.08,repeats:true){[weak self]t in guard let self = self else{t.invalidate();return}; jp += 1
            switch jp{case 1...3:self.poffY = CGFloat(jp)*5;case 4...6:self.poffY = CGFloat(6-(jp-3))*5
            case 7:self.poffY = -1;case 8:self.poffY = 0;self.isPoking = false;t.invalidate();default:break};self.needsDisplay = true}
    }

    override func rightMouseDown(with e:NSEvent) {
        let menu = NSMenu(title:""); menu.autoenablesItems = false
        let pref = NSMenuItem(title:"Preferences...",action:#selector(openSettings),keyEquivalent:","); pref.target = self; menu.addItem(pref)
        menu.addItem(.separator())
        let jrnl = NSMenuItem(title:"Journal Entry...",action:#selector(startJournalMode),keyEquivalent:"j"); jrnl.target = self; menu.addItem(jrnl)
        let jview = NSMenuItem(title:"View Journal",action:#selector(openJournal),keyEquivalent:""); jview.target = self; menu.addItem(jview)
        menu.addItem(.separator())
        let top = NSMenuItem(title:"Always on Top",action:#selector(setLevelTop),keyEquivalent:""); top.target = self; top.state = cfg.windowLevel == 2 ? .on:.off; menu.addItem(top)
        let norm = NSMenuItem(title:"Normal Window",action:#selector(setLevelNormal),keyEquivalent:""); norm.target = self; norm.state = cfg.windowLevel == 1 ? .on:.off; menu.addItem(norm)
        let bot = NSMenuItem(title:"Always at Bottom",action:#selector(setLevelBottom),keyEquivalent:""); bot.target = self; bot.state = cfg.windowLevel == 0 ? .on:.off; menu.addItem(bot)
        menu.addItem(.separator())
        let clr = NSMenuItem(title:"Clear Chat History",action:#selector(clearHist),keyEquivalent:""); clr.target = self; menu.addItem(clr)
        NSMenu.popUpContextMenu(menu,with:e,for:self)
    }
    @objc func openSettings() { AppDelegate.instance?.showSettings() }
    @objc func startJournalMode() { startJournalSession() }
    @objc func openJournal() { AppDelegate.instance?.showJournal() }
    @objc func setLevelTop() { setWindowLevel(2) }
    @objc func setLevelNormal() { setWindowLevel(1) }
    @objc func setLevelBottom() { setWindowLevel(0) }
    @objc func clearHist() {
        // Clear all visible bubbles
        for b in bubbles { b.win.orderOut(nil); b.timer?.invalidate() }
        bubbles.removeAll(); stackTimer?.invalidate(); stackTimer = nil
        dismissFold()
        // Reset counter so watcher picks up fresh
        if let app = AppDelegate.instance { app.cnt = 0 }
        cfg.clearHistory()
        receiveThought(text:"Chat history cleared.", type:"done")
    }
    func setWindowLevel(_ level: Int) {
        cfg.windowLevel = level
        switch level {
        case 0: window?.level = NSWindow.Level(rawValue: -100)   // below all normal windows
        case 1: window?.level = .normal
        default: window?.level = .floating
        }
        cfg.save()
    }
    func setWindowLevelBool(_ top:Bool) { setWindowLevel(top ? 2 : 1) }
    func loadWindowLevel() {
        switch cfg.windowLevel {
        case 0: window?.level = NSWindow.Level(rawValue: -100)
        case 1: window?.level = .normal
        default: window?.level = .floating
        }
    }
    func saveWindowFrame() { guard let f = window?.frame else{return}
        cfg.windowX = f.origin.x; cfg.windowY = f.origin.y; cfg.windowW = f.width; cfg.windowH = f.height; cfg.save() }
}

// ─── Windows ──────────────────────────────────────────────
class DuckWindow:NSWindow {
    override init(contentRect:NSRect,styleMask:NSWindow.StyleMask,backing:NSWindow.BackingStoreType,defer flag:Bool) {
        super.init(contentRect:contentRect,styleMask:.borderless,backing:backing,defer:flag)
        isOpaque = false; backgroundColor = .clear; level = .floating; hasShadow = false
        isMovableByWindowBackground = true; collectionBehavior = [.canJoinAllSpaces,.stationary,.fullScreenAuxiliary]; isReleasedWhenClosed = false
    }
    override var canBecomeKey:Bool{false}; override var canBecomeMain:Bool{false}; override func close(){}
}
class InputWindow:NSWindow { override var canBecomeKey:Bool{true} }

// ─── App Delegate ─────────────────────────────────────────
class AppDelegate:NSObject,NSApplicationDelegate {
    static weak var instance:AppDelegate?
    var win:DuckWindow!; var duck:DuckView!; var cnt = 0; var settingsWC:SettingsWindowController?; var journalWC:JournalWindow?; var spritesheetWC:SpritesheetEditorWindow?
    var statusItem:NSStatusItem?

    func applicationShouldTerminateAfterLastWindowClosed(_:NSApplication)->Bool{false}
    func applicationDidFinishLaunching(_:Notification) {
        AppDelegate.instance = self; setupStatusBar()
        guard let s = NSScreen.main else{return}; let sf = s.visibleFrame; let sz = 48*cfg.scale; let (x,y,w,h) = loadWindow(sf:sf,sz:sz)
        win = DuckWindow(contentRect:NSRect(x:x,y:y,width:w,height:h),styleMask:[],backing:.buffered,defer:false)
        duck = DuckView(frame:NSRect(x:0,y:0,width:w,height:h)); win.contentView = duck; win.makeFirstResponder(duck)
        win.orderFrontRegardless(); duck.loadWindowLevel(); startWatcher(); startWatchdog()
    }
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength); statusItem?.button?.title = "🦆"
        statusItem?.button?.font = NSFont.systemFont(ofSize:14)
        let menu = NSMenu(title:"Duck")
        let pref = NSMenuItem(title:"Preferences...",action:#selector(showSettings),keyEquivalent:","); pref.target = self; menu.addItem(pref)
        let jrnl = NSMenuItem(title:"Journal Entry...",action:#selector(startJournal),keyEquivalent:"j"); jrnl.target = self; menu.addItem(jrnl)
        let jview = NSMenuItem(title:"View Journal",action:#selector(showJournal),keyEquivalent:""); jview.target = self; menu.addItem(jview)
        menu.addItem(.separator())
        let tog = NSMenuItem(title:cfg.alwaysOnTop ? "Move to Normal Layer":"Keep on Top",action:#selector(toggleTop),keyEquivalent:"t"); tog.target = self; menu.addItem(tog)
        let clr = NSMenuItem(title:"Clear Chat History",action:#selector(clearHist),keyEquivalent:""); clr.target = self; menu.addItem(clr)
        menu.addItem(.separator())
        let quit = NSMenuItem(title:"Quit Duck",action:#selector(quitApp),keyEquivalent:"q"); quit.target = self; menu.addItem(quit)
        statusItem?.menu = menu
    }
    @objc func showSettings() {
        if settingsWC == nil{settingsWC = SettingsWindowController(); settingsWC!.onApply = {[weak self] in self?.applySettings()}}
        settingsWC?.showWindow(nil)
    }
    @objc func startJournal() { duck.startJournalSession() }
    @objc func showJournal() { if journalWC == nil{journalWC = JournalWindow()}; journalWC?.showWindow(nil) }
    @objc func showSpritesheetEditor() { if spritesheetWC == nil{spritesheetWC = SpritesheetEditorWindow()}; spritesheetWC?.showWindow(nil) }
    @objc func toggleTop() { cfg.windowLevel = (cfg.windowLevel + 1) % 3; cfg.save(); duck.setWindowLevel(cfg.windowLevel)
        if let m = statusItem?.menu{for i in m.items where i.action==#selector(toggleTop){i.title = cfg.alwaysOnTop ? "Move to Normal Layer":"Keep on Top";break}}}
    @objc func clearHist() { let a = NSAlert(); a.messageText = "Clear Chat History"
        a.informativeText = "Delete all chat history and bubble records."; a.addButton(withTitle:"Clear"); a.addButton(withTitle:"Cancel")
        a.alertStyle = .warning; if a.runModal() == .alertFirstButtonReturn{
            // Clear bubbles too
            for b in duck.bubbles { b.win.orderOut(nil); b.timer?.invalidate() }
            duck.bubbles.removeAll(); duck.stackTimer?.invalidate(); duck.stackTimer = nil
            duck.dismissFold(); cnt = 0; cfg.clearHistory()
            duck.receiveThought(text:"Chat history cleared.", type:"done")
        } }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applySettings() { currentScale = cfg.scale; duck.reloadGIFs()
        let ns = 48*cfg.scale; if let f = win?.frame{win?.setFrame(NSRect(x:f.origin.x-(ns-f.width)/2,y:f.origin.y-(ns-f.height),width:ns,height:ns),display:true,animate:true)
            duck.img.frame = NSRect(x:0,y:0,width:ns,height:ns); duck.needsDisplay = true}
        duck.setWindowLevel(cfg.windowLevel); duck.repositionAll() }
    func startWatchdog() { Timer.scheduledTimer(withTimeInterval:2.0,repeats:true){[weak self]_ in guard let w = self?.win else{return}; if !w.isVisible{w.orderFrontRegardless()}} }
    func loadWindow(sf:NSRect,sz:CGFloat)->(CGFloat,CGFloat,CGFloat,CGFloat) {
        if let x = cfg.windowX,let y = cfg.windowY{return (x,y,max(sz,cfg.windowW ?? sz),max(sz,cfg.windowH ?? sz))}
        return (sf.width-sz-40,sf.height-sz-200,sz,sz) }
    func startWatcher() {
        let d = (THOUGHTS_FILE as NSString).deletingLastPathComponent; try?FileManager.default.createDirectory(atPath:d,withIntermediateDirectories:true)
        if !FileManager.default.fileExists(atPath:THOUGHTS_FILE){try?"[]".write(toFile:THOUGHTS_FILE,atomically:true,encoding:.utf8)}
        DispatchQueue.main.async{[weak self]in self?.c(isInit:true)}
        Timer.scheduledTimer(withTimeInterval:POLL_INTERVAL,repeats:true){[weak self]_ in self?.c(isInit:false)}}
    func c(isInit:Bool) { guard cfg.agentSync else{return}
        guard let ct = try?String(contentsOfFile:THOUGHTS_FILE,encoding:.utf8),let dt = ct.data(using:.utf8),
              let t = try?JSONSerialization.jsonObject(with:dt) as? [[String:Any]] else{return}
        let nc = t.count; if isInit{cnt = nc; for e in t{p(e)}; return}
        if nc>cnt{for i in cnt..<nc{p(t[i])}; cnt = nc} }
    func p(_ t:[String:Any]?) { guard let t = t else{return}
        let tp = t["type"] as? String ?? "", tx = t["text"] as? String ?? ""
        if tp=="permission",let aid = t["action_id"] as? String{duck.showPermission(text:tx,actionId:aid)}
        else{duck.receiveThought(text:tx,type:tp.isEmpty ? "thinking":tp)} }
}

let a = NSApplication.shared; let d = AppDelegate(); a.delegate = d; a.setActivationPolicy(.accessory); a.run()
