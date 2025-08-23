//
//  SquirrelTheme.swift
//  Squirrel（松鼠输入法）
//
//  Created by Leo Liu on 5/9/24.
//
// ========================================================================
// 🎨 松鼠输入法主题系统 - SquirrelTheme 核心模块
// ========================================================================
//
// 📋 模块功能概述：
// 这是松鼠输入法的"视觉设计中心"，负责管理输入法候选框的所有外观和样式。
// 就像一个专业的UI设计师，它决定了用户看到的每一个像素的颜色、字体、布局。
//
// 🏗️ 核心职责：
// 1. 📄 配置解析：从YAML配置文件中读取并解析主题配置
// 2. 🎨 样式计算：根据配置计算出具体的文本样式、段落样式
// 3. 🔤 字体管理：处理字体设置，支持字体级联（多字体备选）
// 4. 🌈 颜色管理：处理各种状态下的颜色配置（普通、高亮、暗色模式）
// 5. 📐 布局控制：管理窗口布局（线性/非线性、垂直/水平）
// 6. 💫 效果设置：控制透明度、阴影、圆角等视觉效果
//
// 🔄 工作流程：
// 1. 接收来自SquirrelConfig的配置数据
// 2. 根据系统暗色/亮色模式选择合适的配色方案
// 3. 解析字体字符串，创建字体级联
// 4. 计算并缓存各种NSAttributedString样式
// 5. 提供计算好的样式给SquirrelView和SquirrelPanel使用
//
// 💡 关键特性：
// - 支持暗色/亮色模式自动切换
// - 懒加载模式，样式只在需要时计算
// - 字体级联支持，自动处理字符回退
// - 完整的配色方案系统
// - 灵活的候选词格式模板
//
// 🎯 在输入法架构中的位置：
// SquirrelConfig → SquirrelTheme → SquirrelView/SquirrelPanel
// (配置加载)   (样式计算)     (界面渲染)
//
// ========================================================================
//
//  这个文件是松鼠输入法的"主题管理中心"，就像是一个专业的室内设计师
//  它负责管理输入法候选框的所有外观设置，包括：
//  
//  1. 颜色主题 - 就像房间的配色方案（背景色、文字色、高亮色等）
//  2. 字体设置 - 就像选择什么样的"字迹"来显示文字
//  3. 布局样式 - 决定候选词是横着排列还是竖着排列
//  4. 尺寸参数 - 控制窗口的大小、圆角、边框、间距等
//  5. 行为选项 - 比如是否半透明、是否记住窗口大小等
//  
//  主要工作流程：
//  1. 从配置文件中读取主题设置
//  2. 根据是否为暗色模式选择合适的配色方案
//  3. 解析字体设置，支持多个备用字体
//  4. 计算各种样式属性（文字样式、段落样式等）
//  5. 提供给界面渲染模块使用
//

// 引入 AppKit 框架，这是 macOS 应用程序的基础框架
// 就像是房子的"地基"，为应用程序提供基本功能，包括颜色、字体等
import AppKit

// 定义一个主题管理类，专门用来管理输入法的外观和样式
// 就像一个"室内设计师"，负责决定输入法窗口长什么样子
// final 表示这个类不能被其他类继承，就像一个"最终版本"的设计方案，不能再修改
final class SquirrelTheme {
  // 定义一些固定的样式参数
  // static 表示这些参数是所有实例共享的，就像班级里的公共物品
  
  // 候选框的偏移高度，让候选框不会紧贴着输入光标
  static let offsetHeight: CGFloat = 5
  
  // 默认字体大小，使用系统默认的字体大小
  static let defaultFontSize: CGFloat = NSFont.systemFontSize
  
  // 状态消息的显示时长（秒），比如"已切换到拼音"这样的提示显示多久
  static let showStatusDuration: Double = 1.2
  
  // 默认字体，使用系统用户字体
  static let defaultFont = NSFont.userFont(ofSize: defaultFontSize)!

  // 定义状态消息的类型枚举
  // 枚举就像是一个"选择题"，只能选择其中的一项
  enum StatusMessageType: String {
    case long    // 长格式显示，比如"当前输入法：拼音"
    case short   // 短格式显示，比如"拼音"
    case mix     // 混合格式显示，结合长短格式的优点
  }
  
  // 定义色彩空间的枚举
  // 不同的色彩空间就像不同的"调色盘"，能显示的颜色范围不同
  enum RimeColorSpace {
    case displayP3  // Display P3 色彩空间，颜色更丰富，就像高级的调色盘
    case sRGB       // sRGB 色彩空间，标准色彩空间，就像普通的调色盘
    
    // 根据名称创建色彩空间对象的静态方法
    static func from(name: String) -> Self {
      if name == "display_p3" {
        return .displayP3  // 如果名称是 display_p3，就返回 Display P3 色彩空间
      } else {
        return .sRGB       // 否则返回 sRGB 色彩空间（默认选项）
      }
    }
  }

  // 定义一些基本的状态属性
  // private(set) 表示只有这个类自己能修改，其他类只能读取
  
  // 主题是否可用，默认是可用的
  private(set) var available = true
  
  // 是否使用原生系统外观，默认是使用的
  private(set) var native = true
  
  // 是否记住窗口大小，默认是记住的
  private(set) var memorizeSize = true
  
  // 当前使用的色彩空间，默认是 sRGB
  private var colorSpace: RimeColorSpace = .sRGB

  // 定义各种颜色属性
  // 就像是为房间的不同部分选择颜色
  
  // 背景颜色，默认使用系统窗口背景色
  var backgroundColor: NSColor = .windowBackgroundColor
  
  // 编辑文本的高亮颜色（正在输入的文本）
  var highlightedPreeditColor: NSColor?
  
  // 选中候选词的背景颜色，默认使用系统选中文本背景色
  var highlightedBackColor: NSColor? = .selectedTextBackgroundColor
  
  // 编辑区域的背景颜色
  var preeditBackgroundColor: NSColor?
  
  // 候选词的背景颜色
  var candidateBackColor: NSColor?
  
  // 边框颜色
  var borderColor: NSColor?

  // 定义各种文本颜色属性
  // private 表示这些颜色只能在这个类内部使用，就像私人的调色板
  
  // 编辑文本的颜色，默认使用系统三级标签颜色
  private var textColor: NSColor = .tertiaryLabelColor
  
  // 编辑文本的高亮颜色，默认使用系统标签颜色
  private var highlightedTextColor: NSColor = .labelColor
  
  // 候选词文本的颜色，默认使用系统二级标签颜色
  private var candidateTextColor: NSColor = .secondaryLabelColor
  
  // 候选词文本的高亮颜色，默认使用系统标签颜色
  private var highlightedCandidateTextColor: NSColor = .labelColor
  
  // 候选词标签的颜色（比如候选词前面的序号）
  private var candidateLabelColor: NSColor?
  
  // 候选词标签的高亮颜色
  private var highlightedCandidateLabelColor: NSColor?
  
  // 注释文本的颜色，默认使用系统三级标签颜色
  private var commentTextColor: NSColor? = .tertiaryLabelColor
  
  // 注释文本的高亮颜色
  private var highlightedCommentTextColor: NSColor?

  // 定义各种尺寸和布局属性
  // private(set) 表示这些属性只能在这个类内部修改
  
  // 圆角半径，决定窗口的圆角程度
  private(set) var cornerRadius: CGFloat = 0
  
  // 高亮项的圆角半径
  private(set) var hilitedCornerRadius: CGFloat = 0
  
  // 周围的额外扩展距离，让窗口不会太紧贴内容
  private(set) var surroundingExtraExpansion: CGFloat = 0
  
  // 阴影大小，决定窗口阴影的明显程度
  private(set) var shadowSize: CGFloat = 0
  
  // 边框宽度（水平方向）
  private(set) var borderWidth: CGFloat = 0
  
  // 边框高度（垂直方向）
  private(set) var borderHeight: CGFloat = 0
  
  // 行间距，决定行与行之间的距离
  private(set) var linespace: CGFloat = 0
  
  // 编辑区域的行间距
  private(set) var preeditLinespace: CGFloat = 0
  
  // 基线偏移，调整文本的垂直位置
  private(set) var baseOffset: CGFloat = 0
  
  // 透明度，1 表示完全不透明，0 表示完全透明
  private(set) var alpha: CGFloat = 1

  // 定义各种布局和行为选项
  
  // 是否使用半透明效果
  private(set) var translucency = false
  
  // 是否互斥显示（同时只显示一个候选词）
  private(set) var mutualExclusive = false
  
  // 是否使用线性布局（横向排列）
  private(set) var linear = false
  
  // 是否使用垂直布局（纵向排列）
  private(set) var vertical = false
  
  // 是否内联显示编辑文本（直接在文本输入位置显示）
  private(set) var inlinePreedit = false
  
  // 是否内联显示候选词（直接在文本输入位置显示）
  private(set) var inlineCandidate = false
  
  // 是否显示分页信息
  private(set) var showPaging = false

  // 候选区最大可见高度（pt）。为 nil 表示不限制，仅受屏幕尺寸限制。
  private(set) var maxCandidateHeight: CGFloat?
  // 预编辑区最大可见高度（pt）。为 nil 表示不限制，仅受屏幕尺寸限制。
  private(set) var maxPreeditHeight: CGFloat?

  // 定义字体相关的属性
  // 就像是为不同的文本选择不同的"笔迹"
  
  // 主要文本的字体数组，可以包含多种字体作为备选
  private var fonts = [NSFont]()
  
  // 标签文本的字体数组（候选词前面的序号）
  private var labelFonts = [NSFont]()
  
  // 注释文本的字体数组
  private var commentFonts = [NSFont]()
  
  // 主要文本的字体大小
  private var fontSize: CGFloat?
  
  // 标签文本的字体大小
  private var labelFontSize: CGFloat?
  
  // 注释文本的字体大小
  private var commentFontSize: CGFloat?

  // 定义候选词的格式模板
  // 就像是决定候选词要怎么"打扮"一下再显示出来
  private var _candidateFormat = "[label]. [candidate] [comment]"
  
  // 状态消息的类型，默认是混合格式
  private(set) var statusMessageType: StatusMessageType = .mix

  // 计算默认字体的属性
  // 如果设置了字体大小，就使用设置的大小；否则使用默认大小
  private var defaultFont: NSFont {
    if let size = fontSize {
  return Self.defaultFont.withSize(size)  // 使用设置的大小
    } else {
  return Self.defaultFont                 // 使用默认大小
    }
  }

  // 主要字体的懒加载属性
  // lazy 表示只有在第一次使用时才会创建，就像"按需制作"
  private(set) lazy var font: NSFont = combineFonts(fonts, size: fontSize) ?? defaultFont
  
  // 标签字体的懒加载属性
  // 如果有专门的标签字体就用标签字体，否则就用主要字体
  private(set) lazy var labelFont: NSFont = {
    if let font = combineFonts(labelFonts, size: labelFontSize ?? fontSize) {
      return font  // 使用专门的标签字体
    } else if let size = labelFontSize {
      return self.font.withSize(size)  // 使用主要字体但调整大小
    } else {
      return self.font  // 直接使用主要字体
    }
  }()
  
  // 注释字体的懒加载属性
  private(set) lazy var commentFont: NSFont = {
    if let font = combineFonts(commentFonts, size: commentFontSize ?? fontSize) {
      return font  // 使用专门的注释字体
    } else if let size = commentFontSize {
      return self.font.withSize(size)  // 使用主要字体但调整大小
    } else {
      return self.font  // 直接使用主要字体
    }
  }()
  // 定义各种文本的样式属性
  // 这些属性就像是"文本的服装"，决定文本的外观
  
  // 候选词的默认样式（颜色、字体、基线偏移）
  private(set) lazy var attrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: candidateTextColor,     // 前景色（文字颜色）
    .font: font,                             // 字体
    .baselineOffset: baseOffset              // 基线偏移（垂直位置调整）
  ]
  
  // 候选词的高亮样式
  private(set) lazy var highlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedCandidateTextColor,  // 高亮文字颜色
    .font: font,                                    // 字体
    .baselineOffset: baseOffset                     // 基线偏移
  ]
  
  // 标签的默认样式
  private(set) lazy var labelAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: candidateLabelColor ?? blendColor(foregroundColor: self.candidateTextColor, backgroundColor: self.backgroundColor),  // 标签颜色
    .font: labelFont,                                                                                                                   // 标签字体
    .baselineOffset: baseOffset + (!vertical ? (font.pointSize - labelFont.pointSize) / 2.5 : 0)                                         // 基线偏移（根据布局调整）
  ]
  
  // 标签的高亮样式
  private(set) lazy var labelHighlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedCandidateLabelColor ?? blendColor(foregroundColor: highlightedCandidateTextColor, backgroundColor: highlightedBackColor),  // 高亮标签颜色
    .font: labelFont,                                                                                                                            // 标签字体
    .baselineOffset: baseOffset + (!vertical ? (font.pointSize - labelFont.pointSize) / 2.5 : 0)                                                // 基线偏移
  ]
  
  // 注释的默认样式
  private(set) lazy var commentAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: commentTextColor ?? candidateTextColor,  // 注释颜色
    .font: commentFont,                                           // 注释字体
    .baselineOffset: baseOffset + (!vertical ? (font.pointSize - commentFont.pointSize) / 2.5 : 0)                             // 基线偏移
  ]
  
  // 注释的高亮样式
  private(set) lazy var commentHighlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedCommentTextColor ?? highlightedCandidateTextColor,  // 高亮注释颜色
    .font: commentFont,                                                               // 注释字体
    .baselineOffset: baseOffset + (!vertical ? (font.pointSize - commentFont.pointSize) / 2.5 : 0)                                   // 基线偏移
  ]
  
  // 编辑文本的默认样式
  private(set) lazy var preeditAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: textColor,        // 编辑文本颜色
    .font: font,                        // 字体
    .baselineOffset: baseOffset         // 基线偏移
  ]
  
  // 编辑文本的高亮样式
  private(set) lazy var preeditHighlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedTextColor,  // 高亮编辑文本颜色
    .font: font,                           // 字体
    .baselineOffset: baseOffset            // 基线偏移
  ]

  // 定义各种段落样式
  // 段落样式就像是"文本的排版规则"，决定段落之间的距离等
  
  // 第一个段落的样式（通常是编辑文本）
  private(set) lazy var firstParagraphStyle: NSParagraphStyle = {
    let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    style.paragraphSpacing = linespace / 2                    // 段落后的间距
    style.paragraphSpacingBefore = preeditLinespace / 2 + hilitedCornerRadius / 2  // 段落前的间距
    return style as NSParagraphStyle
  }()
  
  // 普通段落的样式
  private(set) lazy var paragraphStyle: NSParagraphStyle = {
    let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    style.paragraphSpacing = linespace / 2                    // 段落后的间距
    style.paragraphSpacingBefore = linespace / 2               // 段落前的间距
    return style as NSParagraphStyle
  }()
  
  // 编辑文本的段落样式
  private(set) lazy var preeditParagraphStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    style.paragraphSpacing = preeditLinespace / 2 + hilitedCornerRadius / 2  // 段落后的间距
    style.lineSpacing = linespace                              // 行间距
    return style as NSParagraphStyle
  }()
  // 计算边缘的内边距
  // 内边距就像是"相框的边框宽度"，让内容不会紧贴窗口边缘
  private(set) lazy var edgeInset: NSSize = if self.vertical {
    NSSize(width: borderHeight + cornerRadius, height: borderWidth + cornerRadius)  // 垂直布局的内边距
  } else {
    NSSize(width: borderWidth + cornerRadius, height: borderHeight + cornerRadius)  // 水平布局的内边距
  }
  
  // 边框线条的宽度，取水平和垂直边框的较小值
  private(set) lazy var borderLineWidth: CGFloat = min(borderHeight, borderWidth)
  
  // 候选词格式的属性
  // 提供getter和setter方法，用于处理格式模板的转换
  // 这个属性就像是"模板设计师"，负责定义候选词要如何显示
  private(set) var candidateFormat: String {
    get {
      // 返回内部存储的格式模板
      _candidateFormat
    } set {
      // 当设置新的格式模板时，需要进行一些兼容性转换
      var newTemplate = newValue
      
      // 处理旧版本的 %@ 占位符
      // %@ 是旧版本的格式，现在要转换为新的 [candidate] [comment] 格式
      // 就像把"老式的标签"换成"新式的标签"
      if newTemplate.contains(/%@/) {
        newTemplate.replace(/%@/, with: "[candidate] [comment]")
      }
      
      // 处理旧版本的 %c 占位符
      // %c 表示候选词的标签（序号），现在要转换为 [label] 格式
      if newTemplate.contains(/%c/) {
        newTemplate.replace(/%c/, with: "[label]")
      }
      _candidateFormat = newTemplate
    }
  }
  
  // 计算分页偏移量的计算属性
  // 这个属性决定了分页指示器（如 "1/3" 表示第1页共3页）需要占用多少空间
  // 就像是为"页码标签"预留位置
  var pagingOffset: CGFloat {
    if showPaging {
      // 如果启用了分页显示，就根据字体大小计算需要的空间
      // 取标签字体大小、主字体大小或默认字体大小中的一个，然后乘以1.5作为宽度
      // 1.5倍是一个经验值，确保有足够空间显示分页信息
      (labelFontSize ?? fontSize ?? Self.defaultFontSize) * 1.5
    } else {
      // 如果不显示分页，就不需要额外空间
      0
    }
  }

  // 从配置文件加载主题设置的主要方法
  // 这个方法就像是"室内装修的总承包商"，负责协调所有的装修工作
  // 参数：
  //   config - 配置文件对象，包含所有的主题设置
  //   dark - 是否为暗色模式，决定使用哪套配色方案
  func load(config: SquirrelConfig, dark: Bool) {
    // 第一阶段：加载全局的布局和行为设置
    // 这些设置控制输入法的基本行为，就像是"房子的基本结构"
    
    // 加载布局相关的设置
    // ?= 操作符表示只有在当前值为nil时才会更新，就像"如果没有设置就用配置文件的值"
    linear ?= config.getString("style/candidate_list_layout").map { $0 == "linear" }        // 是否线性布局（横向排列）
    vertical ?= config.getString("style/text_orientation").map { $0 == "vertical" }         // 是否垂直布局（纵向排列）
    inlinePreedit ?= config.getBool("style/inline_preedit")                                  // 是否内联编辑（在输入位置直接显示）
    inlineCandidate ?= config.getBool("style/inline_candidate")                              // 是否内联候选词
    translucency ?= config.getBool("style/translucency")                                    // 是否半透明效果
    mutualExclusive ?= config.getBool("style/mutual_exclusive")                              // 是否互斥显示（同时只显示一个）
    memorizeSize ?= config.getBool("style/memorize_size")                                    // 是否记住窗口大小
  showPaging ?= config.getBool("style/show_paging")                                        // 是否显示分页信息
  maxCandidateHeight ?= config.getDouble("style/max_candidate_height")                     // 候选区最大可见高度
  maxPreeditHeight ?= config.getDouble("style/max_preedit_height")                         // 预编辑区最大可见高度

    // 加载消息和格式相关的设置
    // 这些设置控制信息的显示方式，就像是"标签和说明书的样式"
    statusMessageType ?= .init(rawValue: config.getString("style/status_message_type") ?? "")  // 状态消息类型（长/短/混合格式）
    candidateFormat ?= config.getString("style/candidate_format")                             // 候选词格式模板

    // 第二阶段：加载尺寸和外观相关的设置
    // 这些设置控制窗口的物理外观，就像是"房间的装修细节"
    alpha ?= config.getDouble("style/alpha").map { min(1, max(0, $0)) }                     // 透明度（限制在0-1之间，确保有效范围）
    cornerRadius ?= config.getDouble("style/corner_radius")                                 // 圆角半径（窗口圆角程度）
    hilitedCornerRadius ?= config.getDouble("style/hilited_corner_radius")                   // 高亮项圆角半径
    surroundingExtraExpansion ?= config.getDouble("style/surrounding_extra_expansion")        // 周围额外扩展距离
    borderHeight ?= config.getDouble("style/border_height")                                  // 边框高度（垂直方向）
    borderWidth ?= config.getDouble("style/border_width")                                   // 边框宽度（水平方向）
    linespace ?= config.getDouble("style/line_spacing")                                     // 行间距（行与行之间的距离）
    preeditLinespace ?= config.getDouble("style/spacing")                                   // 编辑区间距
    baseOffset ?= config.getDouble("style/base_offset")                                      // 基线偏移（文字垂直位置微调）
    shadowSize ?= config.getDouble("style/shadow_size").map { max(0, $0) }                 // 阴影大小（不能为负数）

    // 第三阶段：加载字体相关的设置
    // 准备字体配置变量，稍后会用这些变量来创建实际的字体对象
    var fontName = config.getString("style/font_face")                                       // 主要字体名称
    var fontSize = config.getDouble("style/font_point")                                      // 主要字体大小
    var labelFontName = config.getString("style/label_font_face")                             // 标签字体名称（候选词序号的字体）
    var labelFontSize = config.getDouble("style/label_font_point")                           // 标签字体大小
    var commentFontName = config.getString("style/comment_font_face")                         // 注释字体名称（拼音注释的字体）
    var commentFontSize = config.getDouble("style/comment_font_point")                       // 注释字体大小

    // 决定使用哪个配色方案：如果是暗色模式就用暗色方案，否则用普通方案
    // 就像是根据"白天黑夜"选择不同的"房间灯光"
    let colorSchemeOption = dark ? "style/color_scheme_dark" : "style/color_scheme"
    
    // 尝试从配置中获取配色方案名称
    if let colorScheme = config.getString(colorSchemeOption) {
      // 如果配色方案不是 "native"（系统原生），就加载自定义配色
      if colorScheme != "native" {
        // 标记为非原生主题，需要自定义渲染
        native = false
        
        // 构建配色方案在配置文件中的路径前缀
        // 就像是找到"调色盘"在"工具箱"中的位置
        let prefix = "preset_color_schemes/\(colorScheme)"
        
        // 加载色彩空间设置
        colorSpace = .from(name: config.getString("\(prefix)/color_space") ?? "")
        
        // 加载各种背景颜色设置
        // ?= 操作符表示只有在当前值为nil时才会更新，就像"如果没有就设置，有了就不改"
        backgroundColor ?= config.getColor("\(prefix)/back_color", inSpace: colorSpace)                      // 主背景色
        highlightedPreeditColor = config.getColor("\(prefix)/hilited_back_color", inSpace: colorSpace)       // 编辑区高亮背景色
        highlightedBackColor = config.getColor("\(prefix)/hilited_candidate_back_color", inSpace: colorSpace) ?? highlightedPreeditColor  // 候选词高亮背景色
        preeditBackgroundColor = config.getColor("\(prefix)/preedit_back_color", inSpace: colorSpace)        // 编辑区背景色
        candidateBackColor = config.getColor("\(prefix)/candidate_back_color", inSpace: colorSpace)          // 候选词背景色
        borderColor = config.getColor("\(prefix)/border_color", inSpace: colorSpace)                         // 边框颜色

        // 加载各种文字颜色设置
        textColor ?= config.getColor("\(prefix)/text_color", inSpace: colorSpace)                                                          // 普通文字颜色
        highlightedTextColor = config.getColor("\(prefix)/hilited_text_color", inSpace: colorSpace) ?? textColor                         // 高亮文字颜色
        candidateTextColor = config.getColor("\(prefix)/candidate_text_color", inSpace: colorSpace) ?? textColor                         // 候选词文字颜色
        highlightedCandidateTextColor = config.getColor("\(prefix)/hilited_candidate_text_color", inSpace: colorSpace) ?? highlightedTextColor  // 高亮候选词文字颜色
        candidateLabelColor = config.getColor("\(prefix)/label_color", inSpace: colorSpace)                                               // 候选词标签颜色
        highlightedCandidateLabelColor = config.getColor("\(prefix)/hilited_candidate_label_color", inSpace: colorSpace)                  // 高亮候选词标签颜色
        commentTextColor = config.getColor("\(prefix)/comment_text_color", inSpace: colorSpace)                                           // 注释文字颜色
        highlightedCommentTextColor = config.getColor("\(prefix)/hilited_comment_text_color", inSpace: colorSpace)                        // 高亮注释文字颜色

        // 以下是特定配色方案中的配置项，如果存在的话，会覆盖全局 'style' 部分的同名配置
        // 这就像是"特殊场合的服装"，优先级高于日常服装
        
        // 重新加载布局相关设置（使用配色方案中的值，如果存在的话）
        linear ?= config.getString("\(prefix)/candidate_list_layout").map { $0 == "linear" }        // 是否线性布局
        vertical ?= config.getString("\(prefix)/text_orientation").map { $0 == "vertical" }         // 是否垂直布局
        inlinePreedit ?= config.getBool("\(prefix)/inline_preedit")                                  // 是否内联编辑
        inlineCandidate ?= config.getBool("\(prefix)/inline_candidate")                              // 是否内联候选词
        translucency ?= config.getBool("\(prefix)/translucency")                                    // 是否半透明
        mutualExclusive ?= config.getBool("\(prefix)/mutual_exclusive")                              // 是否互斥显示
  showPaging ?= config.getBool("\(prefix)/show_paging")                                        // 是否显示分页
  maxCandidateHeight ?= config.getDouble("\(prefix)/max_candidate_height")                     // 候选区最大可见高度
  maxPreeditHeight ?= config.getDouble("\(prefix)/max_preedit_height")                         // 预编辑区最大可见高度
        candidateFormat ?= config.getString("\(prefix)/candidate_format")                           // 候选词格式
        
        // 重新加载字体相关设置（使用配色方案中的值，如果存在的话）
        fontName ?= config.getString("\(prefix)/font_face")                                         // 主要字体名称
        fontSize ?= config.getDouble("\(prefix)/font_point")                                        // 主要字体大小
        labelFontName ?= config.getString("\(prefix)/label_font_face")                               // 标签字体名称
        labelFontSize ?= config.getDouble("\(prefix)/label_font_point")                             // 标签字体大小
        commentFontName ?= config.getString("\(prefix)/comment_font_face")                           // 注释字体名称
        commentFontSize ?= config.getDouble("\(prefix)/comment_font_point")                         // 注释字体大小

        // 重新加载样式相关设置（使用配色方案中的值，如果存在的话）
        alpha ?= config.getDouble("\(prefix)/alpha").map { max(0, min(1, $0)) }                    // 透明度（限制在0-1之间）
        cornerRadius ?= config.getDouble("\(prefix)/corner_radius")                                 // 圆角半径
        hilitedCornerRadius ?= config.getDouble("\(prefix)/hilited_corner_radius")                   // 高亮圆角半径
        surroundingExtraExpansion ?= config.getDouble("\(prefix)/surrounding_extra_expansion")        // 周围扩展
        borderHeight ?= config.getDouble("\(prefix)/border_height")                                  // 边框高度
        borderWidth ?= config.getDouble("\(prefix)/border_width")                                   // 边框宽度
        linespace ?= config.getDouble("\(prefix)/line_spacing")                                   // 行间距
        preeditLinespace ?= config.getDouble("\(prefix)/spacing")                                 // 编辑间距
        baseOffset ?= config.getDouble("\(prefix)/base_offset")                                    // 基线偏移
        shadowSize ?= config.getDouble("\(prefix)/shadow_size").map { max(0, $0) }              // 阴影大小（不能为负数）
      }
    } else {
      // 如果没有找到配色方案，就标记为不可用
      // 就像是"没有找到设计图纸，无法装修"
      available = false
    }

    // 第四阶段：处理字体设置，将字体名称字符串转换为实际可用的字体对象
    // 这个过程就像是"把购物清单变成实际的商品"
    fonts = decodeFonts(from: fontName)                     // 解析主要字体列表
    self.fontSize = fontSize                                // 设置主要字体大小
    labelFonts = decodeFonts(from: labelFontName ?? fontName)  // 解析标签字体（如果没有设置就使用主要字体）
    self.labelFontSize = labelFontSize                      // 设置标签字体大小
    commentFonts = decodeFonts(from: commentFontName ?? fontName)  // 解析注释字体（如果没有设置就使用主要字体）
    self.commentFontSize = commentFontSize                  // 设置注释字体大小
    
    // 配置加载完成！此时主题对象已经包含了所有必要的设置
    // 后续的懒加载属性（如 font、labelFont、commentFont 等）会在需要时自动计算
  }
}

// 私有扩展部分，包含一些内部使用的辅助方法
// private extension 表示这些方法只能在这个文件内部使用，就像"厨房后厨"，外人不能进入
private extension SquirrelTheme {
  
  // 合并多个字体的方法
  // 这个方法就像是"调配颜料"，把多种字体混合成一个最终的字体
  // 参数：fonts - 字体数组，size - 可选的字体大小
  // 返回：合并后的字体，如果无法合并则返回 nil
  func combineFonts(_ fonts: [NSFont], size: CGFloat?) -> NSFont? {
    // 如果没有字体，就返回 nil（没有颜料就无法调配）
    if fonts.count == 0 { return nil }
    
    // 如果只有一个字体
    if fonts.count == 1 {
      if let size = size {
        // 如果指定了大小，就返回调整大小后的字体
        return fonts[0].withSize(size)
      } else {
        // 否则直接返回原字体
        return fonts[0]
      }
    }
    
    // 如果有多个字体，就创建一个"级联字体"
    // 级联字体就像是"备用方案"，如果第一个字体没有某个字符，就用第二个字体，以此类推
    let attribute = [NSFontDescriptor.AttributeName.cascadeList: fonts[1...].map { $0.fontDescriptor } ]
    let fontDescriptor = fonts[0].fontDescriptor.addingAttributes(attribute)
    return NSFont.init(descriptor: fontDescriptor, size: size ?? fonts[0].pointSize)
  }

  // 从字体字符串解析出字体数组的方法
  // 这个方法就像是"翻译器"，把配置文件中的字体名称翻译成实际可用的字体对象
  // 参数：fontString - 包含字体名称的字符串，可能包含多个字体名称，用逗号分隔
  // 返回：解析出的字体数组
  func decodeFonts(from fontString: String?) -> [NSFont] {
    // 如果没有提供字体字符串，就返回空数组
    guard let fontString = fontString else { return [] }
    
    // 用来记录已经处理过的字体家族，避免重复添加相同的字体
    var seenFontFamilies = Set<String>()
    
    // 按逗号分割字体字符串，得到多个字体名称
    let fontStrings = fontString.split(separator: ",")
    
    // 存储最终解析出的字体数组
    var fonts = [NSFont]()
    
    // 遍历每个字体名称字符串
    for string in fontStrings {
      // 尝试匹配 "字体家族-字体样式" 的格式，比如 "Arial-Bold"
      if let matchedFontName = try? /^\s*(.+)-([^-]+)\s*$/.firstMatch(in: string) {
        let family = String(matchedFontName.output.1)  // 字体家族名称
        let style = String(matchedFontName.output.2)   // 字体样式名称
        
        // 如果这个字体家族已经处理过了，就跳过
        if seenFontFamilies.contains(family) { continue }
        
        // 创建字体描述符，指定家族和样式
        let fontDescriptor = NSFontDescriptor(fontAttributes: [.family: family, .face: style])
        
        // 尝试创建字体对象
        if let font = NSFont(descriptor: fontDescriptor, size: Self.defaultFontSize) {
          fonts.append(font)                    // 添加到字体数组
          seenFontFamilies.insert(family)       // 记录已处理的字体家族
          continue                              // 继续处理下一个字体
        }
      }
      
      // 如果不是 "家族-样式" 格式，就当作直接的字体名称处理
      let fontName = string.trimmingCharacters(in: .whitespaces)  // 去除首尾空格
      
      // 如果这个字体名称已经处理过了，就跳过
      if seenFontFamilies.contains(fontName) { continue }
      
      // 创建字体描述符，直接指定字体名称
      let fontDescriptor = NSFontDescriptor(fontAttributes: [.name: fontName])
      
      // 尝试创建字体对象
      if let font = NSFont(descriptor: fontDescriptor, size: Self.defaultFontSize) {
        fonts.append(font)                    // 添加到字体数组
        seenFontFamilies.insert(fontName)     // 记录已处理的字体名称
        continue                              // 继续处理下一个字体
      }
    }
    
    // 返回解析出的字体数组
    return fonts
  }

  // 混合两种颜色的方法
  // 这个方法就像是"调色师"，把前景色和背景色混合成一个新的颜色
  // 参数：foregroundColor - 前景色，backgroundColor - 背景色（可选）
  // 返回：混合后的颜色
  func blendColor(foregroundColor: NSColor, backgroundColor: NSColor?) -> NSColor {
    // 将前景色转换为 RGB 色彩空间，确保颜色计算的准确性
    let foregroundColor = foregroundColor.usingColorSpace(NSColorSpace.deviceRGB)!
    
    // 将背景色转换为 RGB 色彩空间，如果没有背景色就使用灰色
    let backgroundColor = (backgroundColor ?? NSColor.gray).usingColorSpace(NSColorSpace.deviceRGB)!
    
    // 定义颜色混合的算法
    // 这个算法将前景色的权重设为2，背景色的权重设为1，然后取平均值
    // 就像是"2份前景色 + 1份背景色，然后搅拌均匀"
    func blend(foreground: CGFloat, background: CGFloat) -> CGFloat {
      return (foreground * 2 + background) / 3
    }
    
    // 分别混合红、绿、蓝、透明度四个分量，创建新的颜色
    return NSColor(deviceRed: blend(foreground: foregroundColor.redComponent, background: backgroundColor.redComponent),
                   green: blend(foreground: foregroundColor.greenComponent, background: backgroundColor.greenComponent),
                   blue: blend(foreground: foregroundColor.blueComponent, background: backgroundColor.blueComponent),
                   alpha: blend(foreground: foregroundColor.alphaComponent, background: backgroundColor.alphaComponent))
  }
}

// ==================== SquirrelTheme 类总结 ====================
//
// 这个主题管理类是松鼠输入法界面系统的"大脑"，它的主要职责包括：
//
// 📋 配置管理：
//   - 从配置文件中读取所有的主题设置
//   - 支持全局设置和特定配色方案的设置
//   - 处理暗色/亮色模式的自动切换
//
// 🎨 样式计算：
//   - 计算各种文本样式（颜色、字体、基线偏移等）
//   - 计算段落样式（行间距、段落间距等）
//   - 处理布局相关的尺寸计算
//
// 🔤 字体处理：
//   - 解析字体名称字符串，支持多个备用字体
//   - 创建字体级联（如果第一个字体没有某个字符就用第二个字体）
//   - 分别处理主文字、标签、注释的字体
//
// 🌈 颜色管理：
//   - 支持多种色彩空间（sRGB、Display P3）
//   - 提供颜色混合算法
//   - 处理高亮和普通状态的颜色切换
//
// 💡 使用方式：
//   1. 创建 SquirrelTheme 实例
//   2. 调用 load(config:dark:) 方法加载配置
//   3. 使用各种计算好的样式属性来渲染界面
//
// 这个类采用了懒加载模式，许多复杂的计算只有在真正需要时才会执行，
// 既保证了性能，又确保了在配置加载完成后才进行计算。
//
// ==========================================================
