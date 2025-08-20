//
//  SquirrelApplicationDelegate.swift
//  Squirrel
//
//  Created by Leo Liu on 5/6/24.
//

// 导入必要的系统库
// UserNotifications - 用来显示系统通知的工具包
// Sparkle - 用来处理应用程序自动更新的第三方库
// AppKit - macOS 应用开发的核心界面库
import UserNotifications
import Sparkle
import AppKit

// 定义鼠须管应用程序的主代理类
// final 表示这个类不能被继承，NSObject 是所有 macOS 对象的基类
// 后面那一串是这个类需要遵循的协议（就像签订的合同，规定了这个类必须实现哪些功能）
final class SquirrelApplicationDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
  // 定义一些常量，static 表示这些属性属于类本身，不属于具体的实例
  static let rimeWikiURL = URL(string: "https://github.com/rime/home/wiki")!  // Rime 输入法的帮助文档网址
  static let updateNotificationIdentifier = "SquirrelUpdateNotification"     // 更新通知的标识符
  static let notificationIdentifier = "SquirrelNotification"                 // 普通通知的标识符

  // 定义类的属性（就像这个类的特征和工具）
  let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee  // Rime 输入法引擎的接口，就像遥控器
  var config: SquirrelConfig?      // 配置信息，存储输入法的各种设置
  var panel: SquirrelPanel?        // 输入法面板，就像候选字窗口
  var enableNotifications = false  // 是否启用通知功能的开关
  
  // 自动更新控制器，负责检查和处理应用程序更新
  let updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  
  // 是否支持温和的定时更新提醒
  var supportsGentleScheduledUpdateReminders: Bool {
    true  // 返回 true 表示支持
  }

  // 当即将显示更新界面时会调用这个函数
  // 这就像门铃响了，有人要送更新包裹
  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    NSApp.setActivationPolicy(.regular)  // 让应用变成正常的前台应用（出现在 Dock 栏）
    
    // 如果不是用户主动检查更新，而是自动检查到的
    if !state.userInitiated {
      NSApp.dockTile.badgeLabel = "1"  // 在 Dock 图标上显示数字 1，表示有更新
      
      // 创建一个通知内容，就像写一张便条
      let content = UNMutableNotificationContent()
      content.title = NSLocalizedString("A new update is available", comment: "Update")  // 通知标题
      // 通知内容，把 [version] 替换成实际的版本号
      content.body = NSLocalizedString("Version [version] is now available", comment: "Update").replacingOccurrences(of: "[version]", with: update.displayVersionString)
      
      // 创建通知请求并发送，就像把便条贴到冰箱上
      let request = UNNotificationRequest(identifier: Self.updateNotificationIdentifier, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request)
    }
  }

  // 当用户注意到更新通知时调用这个函数
  // 就像用户看到了冰箱上的便条
  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    NSApp.dockTile.badgeLabel = ""  // 清除 Dock 图标上的数字标记
    // 移除已经显示的更新通知，就像撕掉冰箱上的便条
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationIdentifier])
  }

  // 当更新会话即将结束时调用这个函数
  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)  // 让应用变回辅助应用（不在 Dock 栏显示）
  }

  // 当用户点击通知时会调用这个函数
  // @escaping 表示这个回调函数可能在这个函数执行完后才被调用
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    // 检查是否是点击了更新通知，并且是默认的点击动作
    if response.notification.request.identifier == Self.updateNotificationIdentifier && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      updateController.updater.checkForUpdates()  // 开始检查更新
    }

    completionHandler()  // 告诉系统我们处理完了
  }

  // 应用程序即将完成启动时调用这个函数
  // 就像开店前的最后准备工作
  func applicationWillFinishLaunching(_ notification: Notification) {
    panel = SquirrelPanel(position: .zero)  // 创建输入法候选面板，位置设为原点
    addObservers()  // 添加各种事件监听器，就像安装各种传感器
  }

  // 应用程序即将退出时调用这个函数
  // 就像关店前的清理工作
  func applicationWillTerminate(_ notification: Notification) {
    // swiftlint:disable:next notification_center_detachment
    NotificationCenter.default.removeObserver(self)          // 移除通知中心的监听器
    DistributedNotificationCenter.default().removeObserver(self)  // 移除分布式通知中心的监听器
    panel?.hide()  // 隐藏输入法面板
  }

  // 部署函数 - 重新部署和配置输入法
  // 就像给机器做一次全面的维护和升级
  func deploy() {
    print("Start maintenance...")  // 打印维护开始的消息
    self.shutdownRime()           // 关闭 Rime 输入法引擎
    self.startRime(fullCheck: true)  // 重新启动 Rime 引擎，并进行完整检查
    self.loadSettings()           // 重新加载所有设置
  }

  // 同步用户数据函数
  // 就像备份和同步用户的个人词库和设置
  func syncUserData() {
    print("Sync user data")
    _ = rimeAPI.sync_user_data()  // 调用 Rime API 同步用户数据
  }

  // 打开日志文件夹
  // 就像打开存放维修记录的文件柜
  func openLogFolder() {
    NSWorkspace.shared.open(SquirrelApp.logDir)
  }

  // 打开 Rime 用户数据文件夹
  // 就像打开用户的个人设置和词库存放地
  func openRimeFolder() {
    NSWorkspace.shared.open(SquirrelApp.userDir)
  }

  // 检查更新函数
  func checkForUpdates() {
    if updateController.updater.canCheckForUpdates {  // 如果可以检查更新
      print("Checking for updates")
      updateController.updater.checkForUpdates()     // 执行更新检查
    } else {
      print("Cannot check for updates")              // 无法检查更新时的提示
    }
  }

  // 打开 Wiki 帮助页面
  // 就像打开说明书
  func openWiki() {
    NSWorkspace.shared.open(Self.rimeWikiURL)
  }

  // 显示消息通知的静态函数
  // static 表示这个函数属于类本身，不需要创建实例就能调用
  static func showMessage(msgText: String?) {
    // 获取用户通知中心，就像获取通知发送器
    let center = UNUserNotificationCenter.current()
    
    // 请求通知授权，就像问用户"我可以给你发通知吗？"
    center.requestAuthorization(options: [.alert, .provisional]) { _, error in
      if let error = error {
        print("User notification authorization error: \(error.localizedDescription)")
      }
    }
    
    // 获取通知设置并检查是否允许发送通知
    center.getNotificationSettings { settings in
      // 如果用户授权了通知并且允许显示警告
      if (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) && settings.alertSetting == .enabled {
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Squirrel", comment: "")  // 通知标题
        if let msgText = msgText {
          content.subtitle = msgText  // 如果有消息文本，设置为副标题
        }
        content.interruptionLevel = .active  // 设置为活跃级别的通知
        
        // 创建通知请求并发送
        let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)
        center.add(request) { error in
          if let error = error {
            print("User notification request error: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  // 设置 Rime 输入法引擎的函数
  // 就像给一台新机器进行初始配置
  func setupRime() {
    createDirIfNotExist(path: SquirrelApp.userDir)  // 确保用户数据目录存在
    createDirIfNotExist(path: SquirrelApp.logDir)   // 确保日志目录存在
    
    // swiftlint:disable identifier_name
    // 设置通知处理器，就像安装一个消息接收器
    let notification_handler: @convention(c) (UnsafeMutableRawPointer?, RimeSessionId, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = notificationHandler
    let context_object = Unmanaged.passUnretained(self).toOpaque()
    // swiftlint:enable identifier_name
    rimeAPI.set_notification_handler(notification_handler, context_object)

    // 创建并配置 Rime 特征信息，就像填写机器的配置单
    var squirrelTraits = RimeTraits.rimeStructInit()
    squirrelTraits.setCString(Bundle.main.sharedSupportPath!, to: \.shared_data_dir)  // 共享数据目录
    squirrelTraits.setCString(SquirrelApp.userDir.path(), to: \.user_data_dir)        // 用户数据目录
    squirrelTraits.setCString(SquirrelApp.logDir.path(), to: \.log_dir)               // 日志目录
    squirrelTraits.setCString("Squirrel", to: \.distribution_code_name)               // 发行版代码名称
    squirrelTraits.setCString("鼠鬚管", to: \.distribution_name)                       // 发行版中文名称
    squirrelTraits.setCString(Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String, to: \.distribution_version)  // 版本号
    squirrelTraits.setCString("rime.squirrel", to: \.app_name)                        // 应用名称
    
    rimeAPI.setup(&squirrelTraits)  // 使用这些配置信息设置 Rime 引擎
  }

  // 启动 Rime 引擎的函数
  // fullCheck 参数表示是否进行完整检查
  func startRime(fullCheck: Bool) {
    print("Initializing la rime...")  // 打印初始化消息
    rimeAPI.initialize(nil)           // 初始化 Rime API
    
    // 检查配置更新
    if rimeAPI.start_maintenance(fullCheck) {  // 如果维护成功
      // update squirrel config
      // print("[DEBUG] maintenance suceeds")   // 调试信息（已注释）
      // 部署鼠须管的配置文件
      _ = rimeAPI.deploy_config_file("squirrel.yaml", "config_version")
    } else {
      // print("[DEBUG] maintenance fails")     // 调试信息（已注释）
    }
  }

  // 加载设置的函数
  // 就像从配置文件中读取各种设置项
  func loadSettings() {
    config = SquirrelConfig()  // 创建配置对象
    if !config!.openBaseConfig() {  // 如果无法打开基础配置文件
      return  // 直接返回，不继续执行
    }

    // 根据配置决定是否启用通知
    // 如果设置不是 "never"（从不），就启用通知
    enableNotifications = config!.getString("show_notifications_when") != "never"
    
    // 如果面板和配置都存在，就加载界面配置
    if let panel = panel, let config = self.config {
      panel.load(config: config, forDarkMode: false)  // 加载浅色模式配置
      panel.load(config: config, forDarkMode: true)   // 加载深色模式配置
    }
  }

  // 为特定输入方案加载设置
  // schemaID 是输入方案的标识符，比如 "luna_pinyin"（朙月拼音）
  func loadSettings(for schemaID: String) {
    // 如果方案 ID 为空或者以点开头，就不处理
    if schemaID.count == 0 || schemaID.first == "." {
      return
    }
    
    let schema = SquirrelConfig()  // 创建一个新的配置对象来加载方案配置
    if let panel = panel, let config = self.config {
      // 尝试打开方案的特定配置
      if schema.open(schemaID: schemaID, baseConfig: config) && schema.has(section: "style") {
        // 如果方案有自己的样式配置，就使用方案的配置
        panel.load(config: schema, forDarkMode: false)
        panel.load(config: schema, forDarkMode: true)
      } else {
        // 如果方案没有自己的样式配置，就使用基础配置
        panel.load(config: config, forDarkMode: false)
        panel.load(config: config, forDarkMode: true)
      }
    }
    schema.close()  // 关闭方案配置文件
  }

  // 检测问题启动的函数
  // 防止系统冻结，就像防止机器卡死的安全机制
  func problematicLaunchDetected() -> Bool {
    var detected = false  // 默认没有检测到问题
    
    // 创建日志文件路径，用来记录启动时间
    let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("squirrel_launch.json", conformingTo: .json)
    // print("[DEBUG] archive: \(logFile)")  // 调试信息（已注释）
    
    do {
      // 尝试读取上次启动时间的记录
      let archive = try Data(contentsOf: logFile, options: [.uncached])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .millisecondsSince1970  // 设置日期解码策略
      let previousLaunch = try decoder.decode(Date.self, from: archive)
      
      // 如果上次启动距离现在不到 2 秒，说明可能是连续崩溃重启
      if previousLaunch.timeIntervalSinceNow >= -2 {
        detected = true  // 检测到问题启动
      }
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
      // 如果文件不存在，这是正常情况（第一次启动），不做任何处理

    } catch {
      // 如果出现其他错误，打印错误信息
      print("Error occurred during processing launch time archive: \(error.localizedDescription)")
      return detected
    }
    
    do {
      // 记录当前启动时间到文件
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .millisecondsSince1970  // 设置日期编码策略
      let record = try encoder.encode(Date.now)              // 编码当前时间
      try record.write(to: logFile)                          // 写入文件
    } catch {
      // 如果保存失败，打印错误信息
      print("Error occurred during saving launch time to archive: \(error.localizedDescription)")
    }
    return detected  // 返回检测结果
  }

  // 添加观察者（事件监听器）的函数
  // 就像安装各种传感器来监听系统事件
  // add an awakeFromNib item so that we can set the action method.  Note that
  // any menuItems without an action will be disabled when displayed in the Text
  // Input Menu.
  func addObservers() {
    // 监听工作空间（系统桌面环境）的通知
    let center = NSWorkspace.shared.notificationCenter
    // 监听系统即将关机的通知，就像安装停电报警器
    center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: nil, using: workspaceWillPowerOff)

    // 监听分布式通知（跨应用程序的通知）
    let notifCenter = DistributedNotificationCenter.default()
    // 监听需要重新加载的通知，就像监听"需要重启"的信号
    notifCenter.addObserver(forName: .init("SquirrelReloadNotification"), object: nil, queue: nil, using: rimeNeedsReload)
    // 监听需要同步的通知，就像监听"需要备份"的信号
    notifCenter.addObserver(forName: .init("SquirrelSyncNotification"), object: nil, queue: nil, using: rimeNeedsSync)
  }

  // 当应用程序准备退出时调用这个函数
  // 系统会询问应用程序是否可以退出
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    print("Squirrel is quitting.")        // 打印退出消息
    rimeAPI.cleanup_all_sessions()        // 清理所有 Rime 会话
    return .terminateNow                  // 告诉系统现在可以退出了
  }

}

// 私有的通知处理函数，在文件最外层定义
// @convention(c) 表示这个函数使用 C 语言的调用约定，可以被 C 代码调用
// 这个函数就像一个消息接收员，专门处理从 Rime 引擎发来的各种消息
private func notificationHandler(contextObject: UnsafeMutableRawPointer?, sessionId: RimeSessionId, messageTypeC: UnsafePointer<CChar>?, messageValueC: UnsafePointer<CChar>?) {
  // 从指针恢复应用程序代理对象
  let delegate: SquirrelApplicationDelegate = Unmanaged<SquirrelApplicationDelegate>.fromOpaque(contextObject!).takeUnretainedValue()

  // 将 C 字符串转换为 Swift 字符串
  let messageType = messageTypeC.map { String(cString: $0) }    // 消息类型
  let messageValue = messageValueC.map { String(cString: $0) }  // 消息内容
  
  // 如果是部署相关的消息
  if messageType == "deploy" {
    switch messageValue {
    case "start":
      // 部署开始时显示通知
      SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_start", comment: ""))
    case "success":
      // 部署成功时显示通知
      SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_success", comment: ""))
    case "failure":
      // 部署失败时显示通知
      SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_failure", comment: ""))
    default:
      break  // 其他情况不做处理
    }
    return
  }
  
  // 如果通知功能被关闭，就不处理后续消息
  if !delegate.enableNotifications {
    return
  }

  // 如果是输入方案切换的消息
  if messageType == "schema", let messageValue = messageValue, let schemaName = try? /^[^\/]*\/(.*)$/.firstMatch(in: messageValue)?.output.1 {
    // 使用正则表达式提取方案名称，显示状态消息
    delegate.showStatusMessage(msgTextLong: String(schemaName), msgTextShort: String(schemaName))
    return
  } else if messageType == "option" {
    // 如果是选项切换的消息
    let state = messageValue?.first != "!"  // 如果不是以 ! 开头，表示开启状态
    let optionName = if state {
      messageValue  // 开启状态直接使用原值
    } else {
      // 关闭状态去掉开头的 ! 号
      String(messageValue![messageValue!.index(after: messageValue!.startIndex)...])
    }
    if let optionName = optionName {
      optionName.withCString { name in
        // 获取状态标签的长短两个版本
        let stateLabelLong = delegate.rimeAPI.get_state_label_abbreviated(sessionId, name, state, false)
        let stateLabelShort = delegate.rimeAPI.get_state_label_abbreviated(sessionId, name, state, true)
        let longLabel = stateLabelLong.str.map { String(cString: $0) }
        let shortLabel = stateLabelShort.str.map { String(cString: $0) }
        // 显示状态消息
        delegate.showStatusMessage(msgTextLong: longLabel, msgTextShort: shortLabel)
      }
    }
  }
}

// 为 SquirrelApplicationDelegate 添加私有扩展
// private 表示这些方法只在这个文件内部可见
private extension SquirrelApplicationDelegate {
  // 显示状态消息的内部方法
  // msgTextLong 是长版本的消息，msgTextShort 是短版本的消息
  func showStatusMessage(msgTextLong: String?, msgTextShort: String?) {
    // 如果长消息或短消息不为空，就更新面板状态
    if !(msgTextLong ?? "").isEmpty || !(msgTextShort ?? "").isEmpty {
      panel?.updateStatus(long: msgTextLong ?? "", short: msgTextShort ?? "")
    }
  }

  // 关闭 Rime 引擎的内部方法
  func shutdownRime() {
    config?.close()      // 关闭配置文件
    rimeAPI.finalize()   // 终结 Rime API
  }

  // 工作空间即将关机时的处理方法
  func workspaceWillPowerOff(_: Notification) {
    print("Finalizing before logging out.")  // 打印注销前的最终化消息
    self.shutdownRime()                       // 关闭 Rime 引擎
  }

  // 当收到需要重新加载 Rime 的通知时调用
  func rimeNeedsReload(_: Notification) {
    print("Reloading rime on demand.")  // 打印按需重新加载的消息
    self.deploy()                       // 执行部署操作
  }

  // 当收到需要同步 Rime 的通知时调用
  func rimeNeedsSync(_: Notification) {
    print("Sync rime on demand.")  // 打印按需同步的消息
    self.syncUserData()            // 执行用户数据同步
  }

  // 创建目录的工具方法（如果目录不存在的话）
  // 就像确保某个文件夹存在，如果没有就创建一个
  func createDirIfNotExist(path: URL) {
    let fileManager = FileManager.default  // 获取文件管理器
    if !fileManager.fileExists(atPath: path.path()) {  // 如果路径不存在
      do {
        // 尝试创建目录，withIntermediateDirectories: true 表示会创建中间的所有目录
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
      } catch {
        // 如果创建失败，打印错误信息
        print("Error creating user data directory: \(path.path())")
      }
    }
  }
}

// 为 NSApplication 添加扩展，提供便捷的访问方式
extension NSApplication {
  // 计算属性，用来快速获取鼠须管应用程序代理
  // 就像给 NSApplication 添加了一个快捷方式
  var squirrelAppDelegate: SquirrelApplicationDelegate {
    self.delegate as! SquirrelApplicationDelegate  // 将通用的 delegate 强制转换为鼠须管代理类型
  }
}
