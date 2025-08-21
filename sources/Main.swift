//
//  Main.swift
//  Squirrel（松鼠输入法）
//
//  Created by Leo Liu on 5/10/24.
//

// 引入基础框架，就像做饭前要先准备好厨具一样
import Foundation
// 引入输入法框架，专门用来处理输入法相关的功能
import InputMethodKit

// @main 表示这是程序的入口点，就像房子的正门一样，程序从这里开始运行
@main
struct SquirrelApp {
  // 定义用户目录的路径，这里存放用户的个性化配置文件
  // pwuid = getpwuid(getuid()) 获取当前进程的用户ID, 根据用户ID获取用户的详细信息
  static let userDir = if let pwuid = getpwuid(getuid()) {
    // 如果能获取到用户的主目录，就在里面创建一个"Library/Rime"文件夹
    URL(fileURLWithFileSystemRepresentation: pwuid.pointee.pw_dir, isDirectory: true, relativeTo: nil).appending(components: "Library", "Rime")
  } else {
    // 如果获取失败，就使用系统默认的库目录
    try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Rime", isDirectory: true)
  }
  
  // 定义应用程序的安装目录，就像告诉程序它的"家"在哪里
  static let appDir = "/Library/Input Library/Squirrel.app".withCString { dir in
    URL(fileURLWithFileSystemRepresentation: dir, isDirectory: false, relativeTo: nil)
  }
  
  // 定义日志文件的存放目录，就像记日记的本子放在哪里
  // 临时目录会在电脑重启时被清空
  static let logDir = FileManager.default.temporaryDirectory.appending(component: "rime.squirrel", directoryHint: .isDirectory)

  // 这个警告告诉代码检查工具"我知道这里有点复杂，但是是必要的"
  // swiftlint:disable:next cyclomatic_complexity
  
  // 程序的主要功能函数，就像大脑控制身体一样，这里控制整个程序的运行
  static func main() {
    // 获取 Rime 输入法引擎的接口，就像拿到工具箱一样，里面有很多工具可以用
    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee

    // 创建一个自动内存管理池，就像临时工一样，用完就清理，不会留下垃圾
    let handled = autoreleasepool {
      // 创建一个安装器对象，负责安装和管理输入法
      let installer = SquirrelInstaller()
      
      // 获取命令行参数，就像用户在命令行里输入的指令
      let args = CommandLine.arguments
      
      // 如果用户输入了参数（不只是程序名）
      if args.count > 1 {
        // 根据第一个参数来决定做什么，就像根据菜单点菜一样
        switch args[1] {
        case "--quit":
          // 如果是 --quit 参数，就退出所有正在运行的松鼠输入法
          let bundleId = Bundle.main.bundleIdentifier!
          // 找到所有正在运行的松鼠输入法程序
          let runningSquirrels = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
          // 让它们都退出，就像关掉所有打开的窗口一样
          runningSquirrels.forEach { $0.terminate() }
          return true
          
        case "--reload":
          // 如果是 --reload 参数，就重新加载输入法配置
          // 发送一个通知告诉其他部分"配置有更新，请重新加载"
          DistributedNotificationCenter.default().postNotificationName(.init("SquirrelReloadNotification"), object: nil)
          return true
          
        case "--register-input-source", "--install":
          // 如果是安装参数，就注册输入法到系统中
          // 就像在系统里登记户口一样
          installer.register()
          return true
          
        case "--enable-input-source":
          // 如果是启用输入法的参数
          if args.count > 2 {
            // 如果用户指定了要启用哪些输入模式
            let modes = args[2...].map { SquirrelInstaller.InputMode(rawValue: $0) }.compactMap { $0 }
            if !modes.isEmpty {
              // 启用指定的输入模式
              installer.enable(modes: modes)
              return true
            }
          }
          // 如果没有指定，就启用所有输入模式
          installer.enable()
          return true
          
        case "--disable-input-source":
          // 如果是禁用输入法的参数
          if args.count > 2 {
            // 如果用户指定了要禁用哪些输入模式
            let modes = args[2...].map { SquirrelInstaller.InputMode(rawValue: $0) }.compactMap { $0 }
            if !modes.isEmpty {
              // 禁用指定的输入模式
              installer.disable(modes: modes)
              return true
            }
          }
          // 如果没有指定，就禁用所有输入模式
          installer.disable()
          return true
          
        case "--select-input-source":
          // 如果是选择输入法的参数
          if args.count > 2, let mode = SquirrelInstaller.InputMode(rawValue: args[2]) {
            // 如果用户指定了要选择哪个输入模式
            installer.select(mode: mode)
          } else {
            // 如果没有指定，就让用户选择
            installer.select()
          }
          return true
          
        case "--build":
          // 如果是编译参数，就重新编译输入法的配置文件
          // 显示"正在更新"的消息给用户看
          SquirrelApplicationDelegate.showMessage(msgText: NSLocalizedString("deploy_update", comment: ""))
          
          // 准备编译工具，就像准备好锅碗瓢盆要做饭一样
          var builderTraits = RimeTraits.rimeStructInit()
          // 告诉编译工具这是松鼠输入法的编译器
          builderTraits.setCString("rime.squirrel-builder", to: \.app_name)
          // 初始化编译器
          rimeAPI.setup(&builderTraits)
          rimeAPI.deployer_initialize(nil)
          // 开始编译所有配置文件
          _ = rimeAPI.deploy()
          return true
          
        case "--sync":
          // 如果是同步参数，就同步用户的配置数据
          // 发送同步通知
          DistributedNotificationCenter.default().postNotificationName(.init("SquirrelSyncNotification"), object: nil)
          return true
          
        case "--help":
          // 如果是帮助参数，就显示使用说明
          print(helpDoc)
          return true
          
        default:
          // 如果是其他不认识的参数，就跳过
          break
        }
      }
      // 如果没有处理任何参数，就返回 false
      return false
    }
    
    // 如果已经处理了命令行参数，就直接结束程序
    if handled {
      return
    }

    // 如果没有命令行参数，就启动输入法的主程序
    autoreleasepool {
      // 获取应用程序的标识信息，就像查看身份证一样
      let main = Bundle.main
      // 获取输入法连接的名称，这是系统用来识别输入法的"名字"
      let connectionName = main.object(forInfoDictionaryKey: "InputMethodConnectionName") as! String
      // 创建输入法服务器，就像开店一样，告诉系统"我在这里，可以提供输入法服务"
      _ = IMKServer(name: connectionName, bundleIdentifier: main.bundleIdentifier!)
      
      // 明确加载应用程序包，因为输入法是在后台运行的程序
      // 就像确保所有员工都到岗一样
      let app = NSApplication.shared
      // 创建应用程序的管家，负责管理各种事务
      let delegate = SquirrelApplicationDelegate()
      // 指定管家
      app.delegate = delegate
      // 设置程序在后台运行，不会出现在 Dock 栏
      // 就像一个默默工作的助手，不会打扰用户
      app.setActivationPolicy(.accessory)

      // 切换到包含字典文件的目录，因为 OpenCC（中文转换工具）需要使用相对路径
      // 就像把工作台搬到工具库旁边，方便拿取工具
      FileManager.default.changeCurrentDirectoryPath(main.sharedSupportPath!)

      // 检查程序是否启动正常，有没有出现问题
      if NSApp.squirrelAppDelegate.problematicLaunchDetected() {
        // 如果检测到启动问题
        print("Problematic launch detected!")
        // 准备要朗读的警告信息
        let args = ["Problematic launch detected! Squirrel may be suffering a crash due to improper configuration. Revert previous modifications to see if the problem recurs."]
        // 创建一个语音播报任务
        let task = Process()
        // 使用系统的语音播报工具
        task.executableURL = "/usr/bin/say".withCString { dir in
          URL(fileURLWithFileSystemRepresentation: dir, isDirectory: false, relativeTo: nil)
        }
        // 设置要播报的内容
        task.arguments = args
        // 尝试播放语音警告
        try? task.run()
      } else {
        // 如果启动正常，就进行正常的初始化
        // 设置 Rime 输入法引擎
        NSApp.squirrelAppDelegate.setupRime()
        // 启动 Rime 输入法引擎
        NSApp.squirrelAppDelegate.startRime(fullCheck: false)
        // 加载用户的个性化设置
        NSApp.squirrelAppDelegate.loadSettings()
        // 在控制台打印"松鼠输入法报到！"表示一切正常
        print("Squirrel reporting!")
      }

      // 最后，启动应用程序的主循环，让它开始工作
      // 就像按下启动按钮，让机器开始运转
      app.run()
      // 当程序退出时，打印退出信息
      print("Squirrel is quitting...")
      // 清理 Rime 输入法引擎，就像下班前要整理工具一样
      rimeAPI.finalize()
    }
    // 程序结束
    return
  }

  // 定义帮助文档，告诉用户如何使用这个程序
  // 就像产品说明书一样，告诉用户都有哪些功能
  static let helpDoc = """
支持的命令行参数：
执行操作：
  --quit                     退出所有正在运行的松鼠输入法进程
  --reload                   重新部署输入法配置
  --sync                     同步用户数据
  --build                    编译当前目录下的所有配置文件
安装松鼠输入法：
  --install, --register-input-source    注册输入法到系统
  --enable-input-source [输入法ID...]  启用指定的输入法（可选参数）
  --disable-input-source [输入法ID...] 禁用指定的输入法（可选参数）
  --select-input-source [输入法ID]     选择指定的输入法（可选参数）
"""
}
