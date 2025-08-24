//
//  SquirrelInputController.swift
//  Squirrel（松鼠输入法）
//
//  Created by Leo Liu on 5/7/24.
//

// 引入输入法框架，这是 macOS 系统提供的输入法开发工具包
// 就像是拿到了"输入法开发许可证"，可以合法地开发输入法程序
import InputMethodKit

// 定义输入法控制器类，这是整个输入法的"大脑"
// final 表示这个类不能被其他类继承，就像一个"最终版本"的设计，不能再修改
final class SquirrelInputController: IMKInputController {
  // 定义组合按键的最大数量，就像一个人最多只能同时按下几个键
  // 50 是一个足够大的数字，正常人不可能同时按下这么多键
  private static let keyRollOver = 50

  // 记录未知应用程序的数量，用来给无法识别的应用程序起名字
  // 就像是给不认识的人编号："未知应用1"、"未知应用2"等
  private static var unknownAppCnt: UInt = 0

  // 当前正在使用输入法的应用程序客户端
  // weak 表示如果应用程序关闭了，这个引用就会自动清空，避免内存泄漏
  private weak var client: IMKTextInput?

  // 获取 Rime 输入法引擎的接口，就像拿到工具箱一样，里面有很多工具可以用
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee

  // 当前正在编辑的文本（拼音输入时显示的字母）
  // 比如输入"ni hao"时，这里就会存储"ni hao"
  private var preedit: String = ""

  // 当前选中的文本范围，比如用鼠标拖动选中的文字
  // .empty 表示没有选中任何文字
  private var selRange: NSRange = .empty

  // 光标的位置，就是闪烁的竖线在哪里
  private var caretPos: Int = 0

  // 记录上一次的修饰键状态（Shift、Command、Option等）
  // 用来检测哪些键被按下或释放了
  private var lastModifiers: NSEvent.ModifierFlags = .init()

  // 当前输入法会话的ID，就像每次聊天的房间号
  // 0 表示没有活跃的会话
  private var session: RimeSessionId = 0

  // 当前使用的输入方案ID，比如"拼音"、"五笔"、"仓颉"等
  private var schemaId: String = ""

  // 是否在应用程序内直接显示编辑文本（不弹出候选框）
  // 比如在微信里输入时，直接在输入框显示拼音
  private var inlinePreedit = false

  // 是否在应用程序内直接显示候选词
  // 比如在微信里输入时，直接在输入框下方显示候选词
  private var inlineCandidate = false

  // 以下是组合按键功能的变量（同时按下多个键）
  // 存储组合按键的按键编码数组
  private var chordKeyCodes: [UInt32] = .init(
    repeating: 0, count: SquirrelInputController.keyRollOver)

  // 存储组合按键的修饰键数组
  private var chordModifiers: [UInt32] = .init(
    repeating: 0, count: SquirrelInputController.keyRollOver)

  // 当前组合按键的数量
  private var chordKeyCount: Int = 0

  // 组合按键的定时器，用来检测按键释放
  private var chordTimer: Timer?

  // 组合按键的时间间隔，多久算同时按下
  private var chordDuration: TimeInterval = 0

  // 当前正在使用输入法的应用程序名称
  private var currentApp: String = ""

  // 这个警告告诉代码检查工具"我知道这个方法有点复杂，但是是必要的"
  // swiftlint:disable:next cyclomatic_complexity

  // 处理键盘输入的核心方法，就像输入法的"耳朵"，负责监听所有的按键
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    // 如果事件为空，直接返回 false
    guard let event = event else { return false }

    // 获取当前按下的修饰键（Shift、Command、Option等）
    let modifiers = event.modifierFlags

    // 计算与上一次相比，哪些修饰键的状态发生了变化
    // 就是比较"上次按了什么键"和"这次按了什么键"
    let changes = lastModifiers.symmetricDifference(modifiers)

    // handled 变量用来标记这个按键是否已经被输入法处理了
    // true = 输入法已经处理了这个按键，不需要再传给应用程序
    // false = 输入法没有处理，需要传给应用程序继续处理
    var handled = false

    // 检查输入法会话是否正常，如果不正常就创建新的会话
    if session == 0 || !rimeAPI.find_session(session) {
      createSession()
      if session == 0 {
        // 如果创建会话失败，返回 false 让应用程序处理按键
        return false
      }
    }

    // 更新当前的应用程序客户端
    self.client ?= sender as? IMKTextInput

    // 如果切换到了新的应用程序，就更新应用程序选项
    if let app = client?.bundleIdentifier(), currentApp != app {
      currentApp = app
      updateAppOptions()
    }

    // 根据事件类型来处理不同的情况
    switch event.type {
    case .flagsChanged:
      // 处理修饰键变化（Shift、Command、Option等）
      if lastModifiers == modifiers {
        handled = true
        break
      }

      // 将 macOS 的修饰键转换成 Rime 能理解的格式
      var rimeModifiers: UInt32 = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)

      // 对于修饰键变化事件，从 macOS 10.15 开始才有 keyCode
      let rimeKeycode: UInt32 = SquirrelKeycode.osxKeycodeToRime(
        keycode: event.keyCode, keychar: nil, shift: false, caps: false)

      // 特殊处理大写锁定键
      if changes.contains(.capsLock) {
        // 注意：Rime 要求在修饰键变化之前发送 XK_Caps_Lock，
        // 但 NSFlagsChanged 事件已经包含了变化后的标志。
        // 所以需要反转 kLockMask。
        rimeModifiers ^= kLockMask.rawValue
        _ = processKey(rimeKeycode, modifiers: rimeModifiers)
      }

      // 需要先处理按键释放，再处理按键按下。
      // 因为有时候释放事件会延迟到下一个按键按下时。
      var buffer = [(keycode: UInt32, modifier: UInt32)]()
      for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command]
      where changes.contains(flag) {
        if modifiers.contains(flag) {  // 新按下的修饰键
          buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
        } else {  // 释放的修饰键
          buffer.insert(
            (keycode: rimeKeycode, modifier: rimeModifiers | kReleaseMask.rawValue), at: 0)
        }
      }
      // 处理所有缓冲的按键事件
      for (keycode, modifier) in buffer {
        _ = processKey(keycode, modifiers: modifier)
      }

      // 更新上次的修饰键状态，并刷新界面
      lastModifiers = modifiers
      rimeUpdate()

    case .keyDown:
      // 处理普通按键按下事件
      // 忽略 Command+X 快捷键（已注释掉）
      if modifiers.contains(.command) {
        break
      }

      // 获取按键的编码和字符
      let keyCode = event.keyCode
      var keyChars = event.charactersIgnoringModifiers

      // 打印按键编码和字符值
      print("keyCode: \(keyCode), keyChars: \(keyChars ?? "nil")")

      // 处理大小写相关的字符
      let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
      if let code = keyChars?.first,
        (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII)
      {
        keyChars = event.characters
      }

      // 将 macOS 的按键事件转换成 Rime 的按键事件
      //       if let char = keyChars?.first {
      let char = keyChars?.first
      let rimeKeycode = SquirrelKeycode.osxKeycodeToRime(
        keycode: keyCode, keychar: char,
        shift: modifiers.contains(.shift),
        caps: modifiers.contains(.capsLock))
      if rimeKeycode != 0 {
        let rimeModifiers = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
        // 处理按键并更新界面
        handled = processKey(rimeKeycode, modifiers: rimeModifiers)
        rimeUpdate()
      }
    //       }

    default:
      // 其他类型的事件不处理
      break
    }

    // 返回处理结果
    return handled
  }

  // 选择候选词的方法
  // index: 候选词的序号（0=第一个，1=第二个，以此类推）
  func selectCandidate(_ index: Int) -> Bool {
    // 让 Rime 引擎选择指定序号的候选词
    let success = rimeAPI.select_candidate_on_current_page(session, index)
    if success {
      // 如果选择成功，更新界面显示
      rimeUpdate()
    }
    return success
  }

  // 翻页方法，用来显示上一页或下一页的候选词
  // swiftlint:disable:next identifier_name
  func page(up: Bool) -> Bool {
    var handled = false
    // 让 Rime 引擎翻页，up=true 表示向上翻（上一页），up=false 表示向下翻（下一页）
    handled = rimeAPI.change_page(session, up)
    if handled {
      // 如果翻页成功，更新界面显示
      rimeUpdate()
    }
    return handled
  }

  // 移动光标位置的方法
  // forward: true=向前移动（左移），false=向后移动（右移）
  func moveCaret(forward: Bool) -> Bool {
    // 获取当前光标位置
    let currentCaretPos = rimeAPI.get_caret_pos(session)
    // 获取当前输入的文本
    guard let input = rimeAPI.get_input(session) else { return false }

    if forward {
      // 向前移动光标（左移）
      if currentCaretPos <= 0 {
        return false  // 已经到最左边了，不能再移动
      }
      rimeAPI.set_caret_pos(session, currentCaretPos - 1)
    } else {
      // 向后移动光标（右移）
      let inputStr = String(cString: input)
      if currentCaretPos >= inputStr.utf8.count {
        return false  // 已经到最右边了，不能再移动
      }
      rimeAPI.set_caret_pos(session, currentCaretPos + 1)
    }
    // 更新界面显示
    rimeUpdate()
    return true
  }

  // 告诉系统我们需要处理哪些类型的事件
  override func recognizedEvents(_ sender: Any!) -> Int {
    // 返回我们需要处理的事件类型：按键按下和修饰键变化
    return Int(NSEvent.EventTypeMask.Element(arrayLiteral: .keyDown, .flagsChanged).rawValue)
  }

  // 激活输入法服务器时的处理方法
  // 当用户切换到这个输入法时会调用这个方法
  override func activateServer(_ sender: Any!) {
    // 更新当前的应用程序客户端
    self.client ?= sender as? IMKTextInput

    // 获取键盘布局配置
    var keyboardLayout = NSApp.squirrelAppDelegate.config?.getString("keyboard_layout") ?? ""
    if keyboardLayout == "last" || keyboardLayout == "" {
      // 如果设置为"last"或空，使用系统默认的键盘布局
      keyboardLayout = ""
    } else if keyboardLayout == "default" {
      // 如果设置为"default"，使用 ABC 键盘布局
      keyboardLayout = "com.apple.keylayout.ABC"
    } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
      // 如果不是完整的键盘布局名称，添加前缀
      keyboardLayout = "com.apple.keylayout.\(keyboardLayout)"
    }
    // 如果指定了键盘布局，就应用它
    if keyboardLayout != "" {
      client?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
    }
    // 清空正在编辑的文本
    preedit = ""
  }

  // 初始化方法，当输入法控制器被创建时调用
  override init!(server: IMKServer!, delegate: Any!, client: Any!) {
    // 记录当前的应用程序客户端
    self.client = client as? IMKTextInput

    // 调用父类的初始化方法
    super.init(server: server, delegate: delegate, client: client)

    // 创建输入法会话
    createSession()
  }

  // 停用输入法服务器时的处理方法
  // 当用户切换到其他输入法时会调用这个方法
  override func deactivateServer(_ sender: Any!) {
    // 隐藏输入法界面（候选词窗口等）
    hidePalettes()

    // 提交当前正在编辑的文本
    commitComposition(sender)

    // 清空应用程序客户端引用
    client = nil
  }

  // 隐藏输入法界面
  override func hidePalettes() {
    // 隐藏候选词窗口
    NSApp.squirrelAppDelegate.panel?.hide()

    // 调用父类的隐藏方法
    super.hidePalettes()
  }

  /*!
   @method
   @abstract   当用户操作结束输入会话时调用。
   通常由用户选择新的输入法或键盘布局触发。
   @discussion 当调用此方法时，控制器应该通过调用
   insertText:replacementRange: 将当前输入缓冲区发送到客户端。
   此外，这是清理的时机。
   */
  override func commitComposition(_ sender: Any!) {
    // 更新当前的应用程序客户端
    self.client ?= sender as? IMKTextInput

    // 提交原始输入的文本
    if session != 0 {
      if let input = rimeAPI.get_input(session) {
        // 将输入的文本提交到应用程序
        commit(string: String(cString: input))
        // 清空 Rime 引擎中的编辑状态
        rimeAPI.clear_composition(session)
      }
    }
  }

  // 创建输入法菜单的方法
  // 当用户在菜单栏点击输入法图标时会显示这个菜单
  override func menu() -> NSMenu! {
    // 创建"部署"菜单项（重新编译配置文件）
    let deploy = NSMenuItem(
      title: NSLocalizedString("Deploy", comment: "Menu item"), action: #selector(deploy),
      keyEquivalent: "`")
    deploy.target = self
    deploy.keyEquivalentModifierMask = [.control, .option]

    // 创建"同步用户数据"菜单项
    let sync = NSMenuItem(
      title: NSLocalizedString("Sync user data", comment: "Menu item"),
      action: #selector(syncUserData), keyEquivalent: "")
    sync.target = self

    // 创建"日志"菜单项
    let logDir = NSMenuItem(
      title: NSLocalizedString("Logs...", comment: "Menu item"), action: #selector(openLogFolder),
      keyEquivalent: "")
    logDir.target = self

    // 创建"设置"菜单项
    let setting = NSMenuItem(
      title: NSLocalizedString("Settings...", comment: "Menu item"),
      action: #selector(openRimeFolder), keyEquivalent: "")
    setting.target = self

    // 创建"Rime Wiki"菜单项
    let wiki = NSMenuItem(
      title: NSLocalizedString("Rime Wiki...", comment: "Menu item"), action: #selector(openWiki),
      keyEquivalent: "")
    wiki.target = self

    // 创建"检查更新"菜单项
    let update = NSMenuItem(
      title: NSLocalizedString("Check for updates...", comment: "Menu item"),
      action: #selector(checkForUpdates), keyEquivalent: "")
    update.target = self

    // 创建菜单并添加所有菜单项
    let menu = NSMenu()
    menu.addItem(deploy)
    menu.addItem(sync)
    menu.addItem(logDir)
    menu.addItem(setting)
    menu.addItem(wiki)
    menu.addItem(update)

    return menu
  }

  // 菜单项动作方法

  // 部署配置文件（重新编译）
  @objc func deploy() {
    NSApp.squirrelAppDelegate.deploy()
  }

  // 同步用户数据
  @objc func syncUserData() {
    NSApp.squirrelAppDelegate.syncUserData()
  }

  // 打开日志文件夹
  @objc func openLogFolder() {
    NSApp.squirrelAppDelegate.openLogFolder()
  }

  // 打开 Rime 配置文件夹
  @objc func openRimeFolder() {
    NSApp.squirrelAppDelegate.openRimeFolder()
  }

  // 检查更新
  @objc func checkForUpdates() {
    NSApp.squirrelAppDelegate.checkForUpdates()
  }

  // 打开 Rime Wiki 页面
  @objc func openWiki() {
    NSApp.squirrelAppDelegate.openWiki()
  }

  // 析构方法，当输入法控制器被销毁时调用
  // 就像是打扫房间，在搬走之前把一切都收拾干净
  deinit {
    // 销毁输入法会话
    destroySession()
  }
}

// 私有扩展，包含内部使用的方法
// 就像是家庭的内部事务，外部不需要知道
extension SquirrelInputController {

  // 组合按键定时器触发时的处理方法
  // 当同时按下多个键时，如果超过了设定的时间，就会触发这个方法
  fileprivate func onChordTimer(_: Timer) {
    // 由定时器触发的组合按键释放处理
    var processedKeys = false
    if chordKeyCount > 0 && session != 0 {
      // 模拟按键释放事件
      for i in 0..<chordKeyCount {
        let handled = rimeAPI.process_key(
          session, Int32(chordKeyCodes[i]), Int32(chordModifiers[i] | kReleaseMask.rawValue))
        if handled {
          processedKeys = true
        }
      }
    }
    // 清空组合按键状态
    clearChord()
    if processedKeys {
      // 如果处理了按键，更新界面显示
      rimeUpdate()
    }
  }

  // 更新组合按键状态的方法
  // 当用户按下新的键时，会调用这个方法来更新组合按键的记录
  fileprivate func updateChord(keycode: UInt32, modifiers: UInt32) {
    // 检查这个按键是否已经在组合按键中了
    for i in 0..<chordKeyCount where chordKeyCodes[i] == keycode {
      return  // 如果已经在组合中，就不需要重复添加
    }

    // 检查组合按键数量是否超过限制
    if chordKeyCount >= Self.keyRollOver {
      // 你在作弊！只支持一个人类打字员（手指 <= 10）。
      return
    }

    // 将新的按键添加到组合按键中
    chordKeyCodes[chordKeyCount] = keycode
    chordModifiers[chordKeyCount] = modifiers
    chordKeyCount += 1

    // 重置定时器
    if let timer = chordTimer, timer.isValid {
      timer.invalidate()  // 停止之前的定时器
    }

    // 设置组合按键的时间间隔
    chordDuration = 0.1  // 默认 0.1 秒
    if let duration = NSApp.squirrelAppDelegate.config?.getDouble("chord_duration"), duration > 0 {
      chordDuration = duration  // 使用配置文件中的设置
    }

    // 创建新的定时器
    chordTimer = Timer.scheduledTimer(
      withTimeInterval: chordDuration, repeats: false, block: onChordTimer)
  }

  // 清空组合按键状态的方法
  // 当组合按键结束或者需要取消时调用这个方法
  fileprivate func clearChord() {
    // 清空组合按键数量
    chordKeyCount = 0

    // 停止并清空定时器
    if let timer = chordTimer {
      if timer.isValid {
        timer.invalidate()  // 停止定时器
      }
      chordTimer = nil  // 清空定时器引用
    }
  }

  // 创建输入法会话的方法
  // 每个应用程序使用输入法时都会创建一个独立的会话
  fileprivate func createSession() {
    // 获取应用程序的标识符，如果获取不到就生成一个未知应用的名称
    let app =
      client?.bundleIdentifier()
      ?? {
        SquirrelInputController.unknownAppCnt &+= 1
        return "UnknownApp\(SquirrelInputController.unknownAppCnt)"
      }()

    // 打印调试信息
    print("createSession: \(app)")

    // 记录当前应用程序名称
    currentApp = app

    // 创建 Rime 输入法会话
    session = rimeAPI.create_session()

    // 清空当前输入方案ID
    schemaId = ""

    // 如果会话创建成功，更新应用程序选项
    if session != 0 {
      updateAppOptions()
    }
  }

  // 更新应用程序选项的方法
  // 根据不同的应用程序应用不同的设置
  fileprivate func updateAppOptions() {
    // 如果没有当前应用程序，就不需要更新
    if currentApp == "" {
      return
    }

    // 将当前应用程序信息保存到 Rime 属性中
    // 这样 Rime 引擎就能知道当前正在使用输入法的是哪个应用程序
    rimeAPI.set_property(session, "client_app", currentApp)

    // 获取当前应用程序的选项设置
    if let appOptions = NSApp.squirrelAppDelegate.config?.getAppOptions(currentApp) {
      // 遍历所有选项并应用到 Rime 引擎
      for (key, value) in appOptions {
        print("set app option: \(key) = \(value)")
        rimeAPI.set_option(session, key, value)
      }
    }
  }

  // 销毁输入法会话的方法
  // 当应用程序关闭或切换输入法时调用
  fileprivate func destroySession() {
    // 如果存在活跃的会话，就销毁它
    if session != 0 {
      _ = rimeAPI.destroy_session(session)
      session = 0  // 重置会话ID
    }

    // 清空组合按键状态
    clearChord()
  }

  // 处理按键的核心方法
  // 将按键信息发送给 Rime 引擎进行处理
  fileprivate func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
    // TODO: 在这里添加特殊按键事件的预处理

    // 对于线性候选词列表，方向键的行为可能不同。
    if let panel = NSApp.squirrelAppDelegate.panel {
      if panel.linear != rimeAPI.get_option(session, "_linear") {
        rimeAPI.set_option(session, "_linear", panel.linear)
      }
      // 对于垂直文本，方向键的行为可能不同。
      if panel.vertical != rimeAPI.get_option(session, "_vertical") {
        rimeAPI.set_option(session, "_vertical", panel.vertical)
      }
    }

    // 让 Rime 引擎处理按键
    let handled = rimeAPI.process_key(session, Int32(rimeKeycode), Int32(rimeModifiers))

    // TODO: 在这里添加特殊按键事件的后处理

    // 如果 Rime 引擎没有处理这个按键，就进行特殊处理
    if !handled {
      // 检查是否是 Vim 编辑器的命令模式切换按键
      let isVimBackInCommandMode =
        rimeKeycode == XK_Escape
        || ((rimeModifiers & kControlMask.rawValue != 0)
          && (rimeKeycode == XK_c || rimeKeycode == XK_C || rimeKeycode == XK_bracketleft))
      if isVimBackInCommandMode && rimeAPI.get_option(session, "vim_mode")
        && !rimeAPI.get_option(session, "ascii_mode")
      {
        // 在类 Vim 编辑器的命令模式下关闭中文模式
        rimeAPI.set_option(session, "ascii_mode", true)
      }
    } else {
      // 如果 Rime 引擎处理了按键，检查是否需要处理组合按键
      let isChordingKey =
        switch Int32(rimeKeycode) {
        case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R, XK_Shift_L,
          XK_Shift_R:
          true  // 这些键可以参与组合按键
        default:
          false  // 其他键不参与组合按键
        }

      // 如果启用了组合按键功能且当前按键可以参与组合
      if isChordingKey && rimeAPI.get_option(session, "_chord_typing") {
        updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
      } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
        // 如果不是组合按键，就清空组合按键状态
        clearChord()
      }
    }

    return handled
  }

  // 消耗已提交文本的方法
  // 从 Rime 引擎获取已经确认要输入的文本，并提交到应用程序
  fileprivate func rimeConsumeCommittedText() {
    // 创建一个提交文本的结构体
    var commitText = RimeCommit.rimeStructInit()

    // 从 Rime 引擎获取提交的文本
    if rimeAPI.get_commit(session, &commitText) {
      if let text = commitText.text {
        // 将文本提交到应用程序
        commit(string: String(cString: text))
      }
      // 释放提交文本结构体的内存
      _ = rimeAPI.free_commit(&commitText)
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  // 更新输入法界面显示的方法
  // 这是输入法的"画面更新器"，负责刷新用户看到的所有内容
  fileprivate func rimeUpdate() {
    // print("[DEBUG] rimeUpdate")
    // 首先处理用户已经确认要输入的文字（就像按了空格键确认某个候选词）
    rimeConsumeCommittedText()

    // 创建一个状态结构体，用来存储输入法的当前状态信息
    // 就像是给输入法做个"体检报告"，看看现在是什么状态
    var status = RimeStatus_stdbool.rimeStructInit()
    // 从 Rime 引擎获取当前的状态信息
    if rimeAPI.get_status(session, &status) {
      // 启用特定输入方案的界面样式
      // 比如拼音输入法和五笔输入法可能有不同的界面风格
      // swiftlint:disable:next identifier_name
      // 检查当前使用的输入方案是否发生了变化
      // schema_id 就是输入方案的身份证号，比如"拼音"、"五笔"等
      // 检查当前使用的输入方案是否发生了变化
      // schema_id 就是输入方案的身份证号，比如"拼音"、"五笔"等
      if let schema_id = status.schema_id, schemaId == "" || schemaId != String(cString: schema_id)
      {
        // 更新当前的输入方案ID，就像更换输入法的"工作模式"
        schemaId = String(cString: schema_id)
        // 加载对应输入方案的界面设置，就像换个主题皮肤
        NSApp.squirrelAppDelegate.loadSettings(for: schemaId)
        // 设置内联编辑模式（inline preedit）
        // 内联模式：直接在应用程序的输入框里显示拼音，而不是单独弹窗
        if let panel = NSApp.squirrelAppDelegate.panel {
          // 判断是否使用内联编辑模式
          // 就像选择"在微信输入框里直接显示拼音" 还是 "弹出独立的输入窗口"
          inlinePreedit =
            (panel.inlinePreedit && !rimeAPI.get_option(session, "no_inline"))
            || rimeAPI.get_option(session, "inline")
          // 判断是否使用内联候选词模式
          // 就像选择"在输入框下方直接显示候选词" 还是 "弹出候选词窗口"
          inlineCandidate = panel.inlineCandidate && !rimeAPI.get_option(session, "no_inline")
          // 如果不是内联模式，就在编辑文本中嵌入软光标
          // 软光标：一个虚拟的光标标记，告诉用户当前编辑位置
          rimeAPI.set_option(session, "soft_cursor", !inlinePreedit)
        }
      }
      // 释放状态结构体占用的内存，就像用完餐具要洗干净收起来
      _ = rimeAPI.free_status(&status)
    }

    // 创建一个上下文结构体，用来获取当前输入的详细信息
    // 上下文就像是拍了一张"输入状态的快照"，包含正在输入的内容、候选词等
    var ctx = RimeContext_stdbool.rimeStructInit()
    // 从 Rime 引擎获取当前的输入上下文
    if rimeAPI.get_context(session, &ctx) {
      // 更新预编辑文本（preedit text）
      // 预编辑文本就是用户正在输入但还没确认的文字，比如输入"nihao"时显示的拼音
      let preedit = ctx.composition.preedit.map({ String(cString: $0) }) ?? ""

      // 计算选中文本的开始位置
      let start =
        String.Index(
          preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_start)),
          within: preedit) ?? preedit.startIndex
      // 计算选中文本的结束位置
      let end =
        String.Index(
          preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_end)),
          within: preedit) ?? preedit.startIndex
      // 计算光标的当前位置
      let caretPos =
        String.Index(
          preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos)),
          within: preedit) ?? preedit.startIndex

      // 判断是否使用内联候选词模式
      // 内联候选词：直接在输入框附近显示候选词，而不是弹出独立窗口
      if inlineCandidate {
        // 获取候选词的预览文本
        // 这是用户可能会选择的文字，比如输入"ni"时显示"你"、"尼"等
        var candidatePreview = ctx.commit_text_preview.map { String(cString: $0) } ?? ""
        // 如果同时使用内联预编辑模式
        if inlinePreedit {
          // 如果光标位置在选中区域之后且还没到文本末尾
          // 就把光标后面的文字也加到候选词预览中
          if caretPos >= end && caretPos < preedit.endIndex {
            candidatePreview += preedit[caretPos...]
          }
          // 显示预编辑文本，包含候选词预览
          // 这一步会在输入框中显示完整的预览内容
          show(
            preedit: candidatePreview,
            selRange: NSRange(
              location: start.utf16Offset(in: candidatePreview),
              length: candidatePreview.utf16.distance(from: start, to: candidatePreview.endIndex)),
            caretPos: candidatePreview.utf16.count
              - max(0, preedit.utf16.distance(from: caretPos, to: preedit.endIndex)))
        } else {
          // 如果不使用内联预编辑模式，需要调整候选词预览的显示范围
          // 这里的逻辑是为了正确显示选中的部分和未选中的部分
          if end < caretPos && start < caretPos {
            // 截取候选词预览的一部分，避免显示重复内容
            candidatePreview = String(
              candidatePreview[
                ..<candidatePreview.index(
                  candidatePreview.endIndex,
                  offsetBy: -max(0, preedit.distance(from: end, to: caretPos)))])
          } else if end < preedit.endIndex && caretPos <= start {
            // 另一种情况下的截取逻辑
            candidatePreview = String(
              candidatePreview[
                ..<candidatePreview.index(
                  candidatePreview.endIndex,
                  offsetBy: -max(0, preedit.distance(from: end, to: preedit.endIndex)))])
          }
          // 显示调整后的候选词预览
          show(
            preedit: candidatePreview,
            selRange: NSRange(
              location: start.utf16Offset(in: candidatePreview),
              length: candidatePreview.utf16.distance(from: start, to: candidatePreview.endIndex)),
            caretPos: candidatePreview.utf16.count)
        }
      } else {
        // 如果不使用内联候选词模式，直接显示预编辑文本
        if inlinePreedit {
          // 使用内联预编辑模式：直接在输入框中显示拼音和选中状态
          show(
            preedit: preedit,
            selRange: NSRange(
              location: start.utf16Offset(in: preedit),
              length: preedit.utf16.distance(from: start, to: end)),
            caretPos: caretPos.utf16Offset(in: preedit))
        } else {
          // 小技巧：显示一个非空字符串来防止 iTerm2（终端应用）回显每个字符
          // 注意这里使用的是全角空格 U+3000（中文输入中的空格）
          // 使用半角字符如"..."会导致中文字符编写时基线不稳定
          show(
            preedit: preedit.isEmpty ? "" : "　", selRange: NSRange(location: 0, length: 0),
            caretPos: 0)
        }
      }

      // 更新候选词列表
      // 候选词就是输入法为用户提供的选择项，比如输入"ni"时显示"你"、"尼"、"逆"等
      let numCandidates = Int(ctx.menu.num_candidates)  // 获取候选词的数量
      var candidates = [String]()  // 创建存储候选词文本的数组
      var comments = [String]()  // 创建存储候选词注释的数组（比如拼音、词性等提示信息）
      // 遍历所有候选词，把它们从底层数据结构转换成 Swift 字符串
      for i in 0..<numCandidates {
        let candidate = ctx.menu.candidates[i]  // 获取第 i 个候选词
        // 添加候选词的主要文本（比如"你好"）
        candidates.append(candidate.text.map { String(cString: $0) } ?? "")
        // 添加候选词的注释信息（比如"nǐ hǎo"这样的拼音标注）
        comments.append(candidate.comment.map { String(cString: $0) } ?? "")
      }
      // 创建候选词标签数组，标签就是候选词前面的数字或字母（如 1、2、3 或 a、b、c）
      var labels = [String]()
      // swiftlint:disable identifier_name
      // 检查是否有自定义的选择键（比如用 asdf 代替 1234 来选择候选词）
      if let select_keys = ctx.menu.select_keys {
        // 将选择键字符串转换为单个字符的数组
        // 比如 "1234567890" 变成 ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        labels = String(cString: select_keys).map { String($0) }
      } else if let select_labels = ctx.select_labels {
        // 如果没有选择键，使用预定义的标签
        let pageSize = Int(ctx.menu.page_size)  // 获取每页显示的候选词数量
        // 遍历每页的标签，添加到标签数组中
        for i in 0..<pageSize {
          labels.append(select_labels[i].map { String(cString: $0) } ?? "")
        }
      }
      // swiftlint:enable identifier_name
      // 获取当前页码（从0开始计数，就像数组索引）
      let page = Int(ctx.menu.page_no)
      // 检查是否是最后一页（没有更多候选词了）
      let lastPage = ctx.menu.is_last_page

      // 计算选中范围，用于高亮显示用户选中的文本部分
      let selRange = NSRange(
        location: start.utf16Offset(in: preedit),
        length: preedit.utf16.distance(from: start, to: end))
      // 显示候选词面板（就是弹出的候选词窗口）
      // 这个函数会把所有的信息（预编辑文本、候选词、标签等）传递给界面来显示
      showPanel(
        preedit: inlinePreedit ? "" : preedit,  // 如果是内联模式就不在面板显示预编辑文本
        selRange: selRange,  // 选中的文本范围
        caretPos: caretPos.utf16Offset(in: preedit),  // 光标位置
        candidates: candidates,  // 候选词列表
        comments: comments,  // 候选词注释
        labels: labels,  // 候选词标签（1、2、3等）
        highlighted: Int(ctx.menu.highlighted_candidate_index),  // 当前高亮的候选词索引
        page: page,  // 当前页码
        lastPage: lastPage)  // 是否最后一页
      // 释放上下文结构体占用的内存，避免内存泄漏
      _ = rimeAPI.free_context(&ctx)
    } else {
      // 如果无法获取上下文信息，就隐藏所有输入法界面
      // 这通常发生在输入结束或出现错误时
      hidePalettes()
    }
  }

  // 提交文本的方法
  // 这是把用户最终确认的文字"送达"到应用程序的过程，就像按下回车键确认输入
  fileprivate func commit(string: String) {
    // 检查当前是否有活跃的应用程序客户端，如果没有就直接返回
    guard let client = client else { return }
    // print("[DEBUG] commitString: \(string)")  // 调试信息（已注释）
    // 将确认的文字插入到应用程序中，replacementRange: .empty 表示不替换现有文字，只是插入
    // 就像在微信聊天框中输入文字一样，这一步让文字真正出现在聊天框里
    client.insertText(string, replacementRange: .empty)
    // 清空预编辑文本，因为已经确认输入了
    preedit = ""
    // 隐藏输入法界面（候选词窗口等），因为输入已经完成
    hidePalettes()
  }

  // 显示预编辑文本的方法
  // 这个函数负责在应用程序中显示正在输入但还没确认的文字（比如拼音）
  fileprivate func show(preedit: String, selRange: NSRange, caretPos: Int) {
    // 检查是否有活跃的应用程序客户端
    guard let client = client else { return }
    // print("[DEBUG] showPreeditString: '\(preedit)'")  // 调试信息（已注释）

    // 优化：如果要显示的内容和当前已经显示的完全相同，就不需要重复更新
    // 就像如果电视屏幕上已经是这个画面了，就不需要重新刷新
    if self.preedit == preedit && self.caretPos == caretPos && self.selRange == selRange {
      return
    }

    // 更新内部存储的状态
    self.preedit = preedit  // 保存当前的预编辑文本
    self.caretPos = caretPos  // 保存光标位置
    self.selRange = selRange  // 保存选中范围

    // print("[DEBUG] selRange.location = \(selRange.location), selRange.length = \(selRange.length); caretPos = \(caretPos)")  // 调试信息（已注释）

    // 获取选中文本的起始位置
    let start = selRange.location
    // 创建一个可修改的属性字符串，用来设置文字的显示样式（如颜色、下划线等）
    let attrString = NSMutableAttributedString(string: preedit)

    // 如果选中区域不是从文本开头开始，就为开头部分设置"已转换"的样式
    if start > 0 {
      // 获取"已转换文本"的显示属性（通常是灰色或有下划线）
      let attrs =
        mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: start))!
        as! [NSAttributedString.Key: Any]
      // 应用这些属性到文本的前半部分
      attrString.setAttributes(attrs, range: NSRange(location: 0, length: start))
    }

    // 为剩余部分（用户正在编辑的部分）设置"选中原始文本"的样式
    let remainingRange = NSRange(location: start, length: preedit.utf16.count - start)
    // 获取"选中原始文本"的显示属性（通常有特殊背景色或边框）
    let attrs =
      mark(forStyle: kTSMHiliteSelectedRawText, at: remainingRange)!
      as! [NSAttributedString.Key: Any]
    // 应用这些属性到文本的后半部分
    attrString.setAttributes(attrs, range: remainingRange)

    // 将带有样式的文本设置为"标记文本"显示在应用程序中
    // 标记文本就是告诉系统"这些文字还在编辑中，不是最终确认的"
    client.setMarkedText(
      attrString,
      selectionRange: NSRange(location: caretPos, length: 0),  // 设置光标位置
      replacementRange: .empty)  // 不替换现有文字
  }

  // swiftlint:disable:next function_parameter_count
  // 显示候选词面板的方法
  // 这个函数负责显示输入法的候选词窗口，就像打开一个菜单让用户选择想要的词汇
  fileprivate func showPanel(
    preedit: String,  // 预编辑文本（正在输入的拼音等）
    selRange: NSRange,  // 选中的文本范围
    caretPos: Int,  // 光标位置
    candidates: [String],  // 候选词列表（如"你"、"尼"、"逆"）
    comments: [String],  // 候选词注释（如拼音标注）
    labels: [String],  // 候选词标签（如1、2、3）
    highlighted: Int,  // 当前高亮的候选词序号
    page: Int,  // 当前页码
    lastPage: Bool
  ) {  // 是否是最后一页
    // print("[DEBUG] showPanelWithPreedit:...:")  // 调试信息（已注释）

    // 检查是否有活跃的应用程序客户端
    guard let client = client else { return }

    // 获取输入位置的矩形区域，用来确定候选词窗口应该显示在哪里
    // 就像确定菜单应该弹出在鼠标点击位置附近
    var inputPos = NSRect()
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &inputPos)

    // 获取输入法的候选词面板并更新显示
    if let panel = NSApp.squirrelAppDelegate.panel {
      // 设置面板显示位置（通常在输入框附近）
      panel.position = inputPos
      // 设置面板的输入控制器引用，建立双向连接
      panel.inputController = self
      // 更新面板显示的所有内容：预编辑文本、选中范围、光标位置、候选词等
      panel.update(
        preedit: preedit,  // 要显示的预编辑文本
        selRange: selRange,  // 选中范围
        caretPos: caretPos,  // 光标位置
        candidates: candidates,  // 候选词数组
        comments: comments,  // 注释数组
        labels: labels,  // 标签数组
        highlighted: highlighted,  // 高亮的候选词
        page: page,  // 当前页码
        lastPage: lastPage,  // 是否最后一页
        update: true)  // 强制更新标志
    }
  }
}
