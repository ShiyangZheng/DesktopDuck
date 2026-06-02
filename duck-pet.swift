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
    var bubbleTextWidth: CGFloat { bubbleWidth - 52 }

    override init() { super.init(); load() }

    func load() {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: CONFIG_FILE)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String:Any] else { return }
        if let v = j["scale"] as? Double { scale = max(1.0, min(8.0, CGFloat(v))) }
        // Backward compat: old "alwaysOnTop" Bool → new "windowLevel" Int
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
    convenience init() {
        let w:CGFloat = 480, h:CGFloat = 560
        let win = NSWindow(contentRect:NSRect(x:0,y:0,width:w,height:h),
            styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        win.title = "My Journal"; win.isReleasedWhenClosed = false; win.center()
        self.init(window:win); buildUI(NSSize(width:w,height:h))
    }

    func buildUI(_ sz: NSSize) {
        guard let win = window else { return }
        let w = sz.width
        let sv = NSScrollView(frame: NSRect(x:0,y:40,width:w,height:sz.height-40))
        sv.drawsBackground = false; sv.hasVerticalScroller = true; sv.borderType  = .noBorder; sv.autohidesScrollers = true

        let body = JournalBody(frame: NSRect(x:0,y:0,width:w,height:200))
        sv.documentView = body; win.contentView?.addSubview(sv)

        let addBtn = NSButton(frame:NSRect(x:20,y:8,width:140,height:24))
        addBtn.title = "+ New Entry"; addBtn.bezelStyle  = .rounded
        addBtn.target = self; addBtn.action = #selector(newEntry(_:))
        win.contentView?.addSubview(addBtn)

        let refreshBtn = NSButton(frame:NSRect(x:170,y:8,width:100,height:24))
        refreshBtn.title = "Refresh"; refreshBtn.bezelStyle  = .rounded
        refreshBtn.target = self; refreshBtn.action = #selector(refresh(_:))
        win.contentView?.addSubview(refreshBtn)

        body.refreshEntries()
        body.frame.size.height = max(body.calculatedHeight, sz.height)
    }

    @objc func newEntry(_ s: Any?) { AppDelegate.instance?.duck?.startJournalSession() }
    @objc func refresh(_ s: Any?) {
        // Trigger summary generation for all pending entries
        let sp = (CommandLine.arguments[0] as NSString).deletingLastPathComponent + "/../Resources/pet-journal-summary.py"
        DispatchQueue.global().async {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            t.arguments = [sp, "--all"]
            try? t.run()
            t.waitUntilExit()
            // Refresh the view after summary generation
            DispatchQueue.main.async {
                guard let sv = self.window?.contentView?.subviews.first(where:{$0 is NSScrollView}) as? NSScrollView,
                      let body = sv.documentView as? JournalBody else { return }
                body.refreshEntries(); body.frame.size.height = max(body.calculatedHeight, 560)
            }
        }
    }
    override func showWindow(_ s: Any?) { window?.center(); super.showWindow(s) }
}

class JournalBody: NSView {
    var calculatedHeight: CGFloat = 100
    override var isFlipped: Bool { true }

    func refreshEntries() {
        subviews.forEach { $0.removeFromSuperview() }
        guard let d = try? Data(contentsOf:URL(fileURLWithPath:JOURNAL_FILE)),
              let entries = try? JSONSerialization.jsonObject(with:d) as? [[String:Any]], !entries.isEmpty else {
            let lb = NSTextField(frame:NSRect(x:20,y:10,width:bounds.width-40,height:30))
            lb.stringValue = "No journal entries yet.\nStart a journal entry from Preferences or right-click the duck."
            lb.isBezeled = false; lb.drawsBackground = false; lb.isEditable = false
            lb.font  = .systemFont(ofSize:12); lb.textColor  = .secondaryLabelColor
            lb.lineBreakMode  = .byWordWrapping; addSubview(lb)
            calculatedHeight = 60; return
        }
        var y: CGFloat = 12, w = bounds.width - 40
        let ts = DateFormatter(); ts.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for entry in entries.reversed() {
            let time = entry["time"] as? String ?? ""
            let template = entry["template"] as? String ?? ""
            let summary = entry["summary"] as? String ?? ""

            // Date header
            if let t = ts.date(from: time) {
                let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "MMM d, yyyy 'at' HH:mm"
                let dl = NSTextField(frame: NSRect(x: 20, y: y, width: w, height: 20))
                dl.stringValue = "📅  " + df.string(from: t)
                dl.isBezeled = false; dl.drawsBackground = false; dl.isEditable = false
                dl.font = NSFont.boldSystemFont(ofSize: 13); dl.textColor = .labelColor
                addSubview(dl)
                y += 24
            }

            if !template.isEmpty {
                let tl = NSTextField(frame: NSRect(x: 20, y: y, width: w, height: 16))
                tl.stringValue = "Template: " + template
                tl.isBezeled = false; tl.drawsBackground = false; tl.isEditable = false
                tl.font = .systemFont(ofSize: 11); tl.textColor = .secondaryLabelColor
                addSubview(tl)
                y += 20
            }

            if !summary.isEmpty {
                let sh: CGFloat = min(CGFloat(summary.count / 2) + 40, 200)
                let sv = NSScrollView(frame: NSRect(x: 18, y: y, width: w + 4, height: sh + 8))
                sv.hasVerticalScroller = true; sv.drawsBackground = false
                sv.borderType = .noBorder; sv.autohidesScrollers = true
                let stv = NSTextView(frame: NSRect(x: 0, y: 0, width: w, height: sh))
                stv.string = summary; stv.font = .systemFont(ofSize: 11)
                stv.textColor = .labelColor; stv.isEditable = false
                stv.drawsBackground = false; stv.isRichText = false
                sv.documentView = stv
                addSubview(sv)
                y += sh + 14
            } else {
                let pl = NSTextField(frame: NSRect(x: 20, y: y, width: w, height: 16))
                pl.stringValue = "⏳ Summary pending — click Refresh to generate"
                pl.isBezeled = false; pl.drawsBackground = false; pl.isEditable = false
                pl.font = .systemFont(ofSize: 11); pl.textColor = .secondaryLabelColor
                addSubview(pl)
                y += 20
            }

            // Separator
            let sep = NSView(frame: NSRect(x: 20, y: y + 2, width: w, height: 1))
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
            addSubview(sep)
            y += 16
        }
        calculatedHeight = max(y + 20, 100)
    }
}

// ─── Settings Window ──────────────────────────────────────
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
        let m:CGFloat = 24; let body = NSView(frame:NSRect(x:0,y:0,width:w,height:1680)); var y:CGFloat = 1660

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
        (scaleSlider,scaleLabel) = mkSlider(min:1,max:8,cur:Double(cfg.scale),tag:1); mkSub("Pet Size")
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

        // AI Character Generation
        sec("Generate Character Image")
        mkSub("Describe the character you want")
        genPrompt = NSTextField(frame:NSRect(x:m,y:y-22,width:w-m*2-80,height:22))
        genPrompt.placeholderString = "e.g. cute yellow rubber duck, chibi style"
        genPrompt.isBezeled = true; genPrompt.bezelStyle = .squareBezel
        genPrompt.font = .systemFont(ofSize:11); genPrompt.delegate = self; body.addSubview(genPrompt)
        genButton = NSButton(frame:NSRect(x:w-m-76,y:y-22,width:80,height:22))
        genButton.title = "Generate"; genButton.bezelStyle = .inline; genButton.font = .systemFont(ofSize:11)
        genButton.target = self; genButton.action = #selector(generateCharacter); body.addSubview(genButton)
        y -= 28

        genSpinner = NSProgressIndicator(frame:NSRect(x:m,y:y-16,width:16,height:16))
        genSpinner.style = .spinning; genSpinner.isDisplayedWhenStopped = false
        genSpinner.controlSize = .small; body.addSubview(genSpinner)
        genStatus = NSTextField(frame:NSRect(x:m+20,y:y-16,width:w-m*2-20,height:16))
        genStatus.isBezeled = false; genStatus.drawsBackground = false; genStatus.isEditable = false
        genStatus.font = .systemFont(ofSize:10); genStatus.textColor = .secondaryLabelColor; body.addSubview(genStatus)
        y -= 20

        genPreview = NSImageView(frame:NSRect(x:m,y:y-68,width:w-m*2,height:68))
        genPreview.imageScaling = .scaleProportionallyUpOrDown; genPreview.wantsLayer = true
        genPreview.layer?.backgroundColor = NSColor(white:0.95,alpha:1).cgColor
        genPreview.layer?.cornerRadius = 6; body.addSubview(genPreview)
        y -= 76

        let applyBtn = NSButton(frame:NSRect(x:m,y:y-20,width:120,height:20))
        applyBtn.title = "Apply"; applyBtn.bezelStyle = .inline; applyBtn.font = .systemFont(ofSize:10)
        applyBtn.target = self; applyBtn.action = #selector(applyGenIdle); body.addSubview(applyBtn)

        let restoreBtn = NSButton(frame:NSRect(x:m+126,y:y-20,width:160,height:20))
        restoreBtn.title = "Restore Default Duck"; restoreBtn.bezelStyle = .inline; restoreBtn.font = .systemFont(ofSize:10)
        restoreBtn.target = self; restoreBtn.action = #selector(restoreDefaultDuck); body.addSubview(restoreBtn)
        y -= 28

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
        (bubbleWidthSlider,bwLabel) = mkSlider(min:160,max:400,cur:Double(cfg.bubbleWidth),tag:2); mkSub("Width (px)")
        (bubbleHeightSlider,bhLabel) = mkSlider(min:80,max:600,cur:Double(cfg.bubbleMaxHeight),tag:3); mkSub("Max Height (px, scrollable)")
        (maxVisibleSlider,mvLabel) = mkSlider(min:1,max:10,cur:Double(cfg.maxVisible),tag:4); mkSub("Max Visible Bubbles")
        (timeoutSlider,timeoutLabel) = mkSlider(min:0,max:300,cur:cfg.bubbleTimeout,tag:7); mkSub("Bubble Timeout (seconds, 0 = never)")

        // Chat
        sec("Chat & Memory")
        mkSub("Chat History File")
        histPath = NSTextField(frame:NSRect(x:m,y:y-22,width:w-m*2-60,height:22))
        histPath.stringValue = cfg.chatHistoryPath; histPath.isBezeled = true; histPath.bezelStyle = .squareBezel
        histPath.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular); histPath.delegate = self; y -= 22; body.addSubview(histPath)
        let hb = NSButton(frame:NSRect(x:w-m-56,y:y-6,width:60,height:20))
        hb.title = "Browse..."; hb.bezelStyle = .inline; hb.font = .systemFont(ofSize:10)
        hb.target = self; hb.action = #selector(chooseHistPath); y -= 26; body.addSubview(hb)
        (ctxSlider,ctxLabel) = mkSlider(min:0,max:50,cur:Double(cfg.contextWindow),tag:5); mkSub("Context Window (past turns included)")
        (compSlider,compLabel) = mkSlider(min:5,max:200,cur:Double(cfg.compressThreshold),tag:6); mkSub("Compress Threshold (turns before summarizing)")

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
        llmKey = NSSecureTextField(frame:NSRect(x:m,y:y-22,width:w-m*2,height:22))
        llmKey.stringValue = cfg.llmApiKey; llmKey.font = NSFont.monospacedSystemFont(ofSize:10,weight:.regular)
        llmKey.delegate = self; y -= 28; body.addSubview(llmKey)
        mkSub("API Key (auto-saved)")
        y += 28; llmModel = mkTF("Model Name"); llmModel.stringValue = cfg.llmModel
        llmUrl = mkTF("API Endpoint URL"); llmUrl.stringValue = cfg.llmUrl

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
        aboutL.stringValue = "Desktop Duck Pet v1.0\nRight-click → Preferences | Menu bar → All settings"
        aboutL.isBezeled = false; aboutL.drawsBackground = false; aboutL.isEditable = false
        aboutL.font = .systemFont(ofSize:10); aboutL.textColor = .secondaryLabelColor; aboutL.lineBreakMode = .byWordWrapping; body.addSubview(aboutL)

        sv.documentView = body; win.contentView = sv; updateLabels()
    }

    override func showWindow(_ s: Any?) { window?.center(); super.showWindow(s); NSApp.activate(ignoringOtherApps:true) }

    @objc func sliderChanged(_:NSSlider) { updateLabels(); applyConfig() }
    @objc func levelChanged(_ sender: NSPopUpButton) {
        cfg.windowLevel = sender.indexOfSelectedItem
        cfg.save(); onApply?()
    }
    @objc func agentToggled(_ s:NSButton) { cfg.agentSync = (s.state == .on); cfg.save() }

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
        let exe = CommandLine.arguments[0]
        let resDir = ((exe as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../Resources/")
        let destPath = resDir + "/duck-idle.gif"
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
            duck.receiveThought(text: "🖼️ New look applied!", type: "done")
        }
    }
    @objc func restoreDefaultDuck() {
        let exe = CommandLine.arguments[0]
        let resDir = ((exe as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../Resources/")
        let backupPath = resDir + "/duck-idle.gif.bak"
        let destPath = resDir + "/duck-idle.gif"
        if FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.removeItem(atPath: destPath)
            try? FileManager.default.copyItem(atPath: backupPath, toPath: destPath)
        }
        cfg.idleGifPath = ""
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
        idleGIF = NSImage(contentsOfFile:cfg.idleGifPath.isEmpty ? dir+"/duck-idle.gif":cfg.idleGifPath)
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
        pushBubble(text:"📓 Journal saved. View Journal → Refresh for AI summary.", type:"done")
    }

    func saveJournalTranscript() {
        let ts = DateFormatter(); ts.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = ts.string(from: Date())

        // Load existing entries
        var entries: [[String:Any]] = []
        if let d = try? Data(contentsOf: URL(fileURLWithPath: JOURNAL_FILE)),
           let e = try? JSONSerialization.jsonObject(with: d) as? [[String:Any]] { entries = e }
        entries.append([
            "time": now,
            "template": cfg.journalTemplate,
            "type": "journal",
            "summary": "",
            "transcript": journalTranscript
        ])

        // Save to file
        do {
            let data = try JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: JOURNAL_FILE))
        } catch {
            pushBubble(text: "❌ Failed to save journal: \(error.localizedDescription)", type: "done")
            return
        }

        // Spawn summary generation for this entry asynchronously
        let sp = scriptsDir() + "pet-journal-summary.py"
        let pyPath = "/usr/local/bin/python3"
        if !FileManager.default.fileExists(atPath: sp) {
            pushBubble(text: "⚠️ Summary script not found at \(sp)", type: "done")
            return
        }
        DispatchQueue.global().async {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: pyPath)
            t.arguments = [sp, now]
            do { try t.run() } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.pushBubble(text: "❌ Summary generation failed: \(error.localizedDescription)", type: "done")
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
    var win:DuckWindow!; var duck:DuckView!; var cnt = 0; var settingsWC:SettingsWindowController?; var journalWC:JournalWindow?
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
