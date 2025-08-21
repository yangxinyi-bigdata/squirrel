//
//  SquirrelTheme.swift
//  Squirrel（松鼠输入法）
//
//  Created by Leo Liu on 5/9/24.
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
  private(set) var candidateFormat: String {
    get {
      _candidateFormat  // 返回内部存储的格式
    } set {
      var newTemplate = newValue
      // 如果新模板包含 %@ 占位符，就替换为 [candidate] [comment]
      if newTemplate.contains(/%@/) {
        newTemplate.replace(/%@/, with: "[candidate] [comment]")
      }
      // 如果新模板包含 %c 占位符，就替换为 [label]
      if newTemplate.contains(/%c/) {
        newTemplate.replace(/%c/, with: "[label]")
      }
      _candidateFormat = newTemplate
    }
  }
  
  // 计算分页偏移量
  // 如果启用了分页显示，就计算分页符号需要的空间
  var pagingOffset: CGFloat {
    if showPaging {
      (labelFontSize ?? fontSize ?? Self.defaultFontSize) * 1.5  // 分页符号的宽度
    } else {
      0  // 不显示分页
    }
  }

  // 从配置文件加载主题设置
  // 这个方法就像是"根据设计图装修房间"，把配置文件中的设置应用到主题上
  func load(config: SquirrelConfig, dark: Bool) {
    // 加载布局相关的设置
    // ?= 操作符表示只有在当前值为nil时才会更新
    linear ?= config.getString("style/candidate_list_layout").map { $0 == "linear" }        // 是否线性布局
    vertical ?= config.getString("style/text_orientation").map { $0 == "vertical" }         // 是否垂直布局
    inlinePreedit ?= config.getBool("style/inline_preedit")                                  // 是否内联编辑
    inlineCandidate ?= config.getBool("style/inline_candidate")                              // 是否内联候选词
    translucency ?= config.getBool("style/translucency")                                    // 是否半透明
    mutualExclusive ?= config.getBool("style/mutual_exclusive")                              // 是否互斥显示
    memorizeSize ?= config.getBool("style/memorize_size")                                    // 是否记住大小
    showPaging ?= config.getBool("style/show_paging")                                        // 是否显示分页
    maxCandidateHeight ?= config.getDouble("style/max_candidate_height")                     // 候选区最大可见高度

    // 加载消息相关的设置
    statusMessageType ?= .init(rawValue: config.getString("style/status_message_type") ?? "")  // 状态消息类型
    candidateFormat ?= config.getString("style/candidate_format")                             // 候选词格式

    // 加载尺寸相关的设置
    alpha ?= config.getDouble("style/alpha").map { min(1, max(0, $0)) }                     // 透明度（限制在0-1之间）
    cornerRadius ?= config.getDouble("style/corner_radius")                                 // 圆角半径
    hilitedCornerRadius ?= config.getDouble("style/hilited_corner_radius")                   // 高亮圆角半径
    surroundingExtraExpansion ?= config.getDouble("style/surrounding_extra_expansion")        // 周围扩展
    borderHeight ?= config.getDouble("style/border_height")                                  // 边框高度
    borderWidth ?= config.getDouble("style/border_width")                                   // 边框宽度
    linespace ?= config.getDouble("style/line_spacing")                                     // 行间距
    preeditLinespace ?= config.getDouble("style/spacing")                                   // 编辑间距
    baseOffset ?= config.getDouble("style/base_offset")                                      // 基线偏移
    shadowSize ?= config.getDouble("style/shadow_size").map { max(0, $0) }                 // 阴影大小（不能为负数）

    // 加载字体相关的设置
    var fontName = config.getString("style/font_face")                                       // 主要字体名称
    var fontSize = config.getDouble("style/font_point")                                      // 主要字体大小
    var labelFontName = config.getString("style/label_font_face")                             // 标签字体名称
    var labelFontSize = config.getDouble("style/label_font_point")                           // 标签字体大小
    var commentFontName = config.getString("style/comment_font_face")                         // 注释字体名称
    var commentFontSize = config.getDouble("style/comment_font_point")                       // 注释字体大小

    let colorSchemeOption = dark ? "style/color_scheme_dark" : "style/color_scheme"
    if let colorScheme = config.getString(colorSchemeOption) {
      if colorScheme != "native" {
        native = false
        let prefix = "preset_color_schemes/\(colorScheme)"
        colorSpace = .from(name: config.getString("\(prefix)/color_space") ?? "")
        backgroundColor ?= config.getColor("\(prefix)/back_color", inSpace: colorSpace)
        highlightedPreeditColor = config.getColor("\(prefix)/hilited_back_color", inSpace: colorSpace)
        highlightedBackColor = config.getColor("\(prefix)/hilited_candidate_back_color", inSpace: colorSpace) ?? highlightedPreeditColor
        preeditBackgroundColor = config.getColor("\(prefix)/preedit_back_color", inSpace: colorSpace)
        candidateBackColor = config.getColor("\(prefix)/candidate_back_color", inSpace: colorSpace)
        borderColor = config.getColor("\(prefix)/border_color", inSpace: colorSpace)

        textColor ?= config.getColor("\(prefix)/text_color", inSpace: colorSpace)
        highlightedTextColor = config.getColor("\(prefix)/hilited_text_color", inSpace: colorSpace) ?? textColor
        candidateTextColor = config.getColor("\(prefix)/candidate_text_color", inSpace: colorSpace) ?? textColor
        highlightedCandidateTextColor = config.getColor("\(prefix)/hilited_candidate_text_color", inSpace: colorSpace) ?? highlightedTextColor
        candidateLabelColor = config.getColor("\(prefix)/label_color", inSpace: colorSpace)
        highlightedCandidateLabelColor = config.getColor("\(prefix)/hilited_candidate_label_color", inSpace: colorSpace)
        commentTextColor = config.getColor("\(prefix)/comment_text_color", inSpace: colorSpace)
        highlightedCommentTextColor = config.getColor("\(prefix)/hilited_comment_text_color", inSpace: colorSpace)

        // the following per-color-scheme configurations, if exist, will
        // override configurations with the same name under the global 'style'
        // section
        linear ?= config.getString("\(prefix)/candidate_list_layout").map { $0 == "linear" }
        vertical ?= config.getString("\(prefix)/text_orientation").map { $0 == "vertical" }
        inlinePreedit ?= config.getBool("\(prefix)/inline_preedit")
        inlineCandidate ?= config.getBool("\(prefix)/inline_candidate")
        translucency ?= config.getBool("\(prefix)/translucency")
        mutualExclusive ?= config.getBool("\(prefix)/mutual_exclusive")
        showPaging ?= config.getBool("\(prefix)/show_paging")
        maxCandidateHeight ?= config.getDouble("\(prefix)/max_candidate_height")
        candidateFormat ?= config.getString("\(prefix)/candidate_format")
        fontName ?= config.getString("\(prefix)/font_face")
        fontSize ?= config.getDouble("\(prefix)/font_point")
        labelFontName ?= config.getString("\(prefix)/label_font_face")
        labelFontSize ?= config.getDouble("\(prefix)/label_font_point")
        commentFontName ?= config.getString("\(prefix)/comment_font_face")
        commentFontSize ?= config.getDouble("\(prefix)/comment_font_point")

        alpha ?= config.getDouble("\(prefix)/alpha").map { max(0, min(1, $0)) }
        cornerRadius ?= config.getDouble("\(prefix)/corner_radius")
        hilitedCornerRadius ?= config.getDouble("\(prefix)/hilited_corner_radius")
        surroundingExtraExpansion ?= config.getDouble("\(prefix)/surrounding_extra_expansion")
        borderHeight ?= config.getDouble("\(prefix)/border_height")
        borderWidth ?= config.getDouble("\(prefix)/border_width")
        linespace ?= config.getDouble("\(prefix)/line_spacing")
        preeditLinespace ?= config.getDouble("\(prefix)/spacing")
        baseOffset ?= config.getDouble("\(prefix)/base_offset")
        shadowSize ?= config.getDouble("\(prefix)/shadow_size").map { max(0, $0) }
      }
    } else {
      available = false
    }

    fonts = decodeFonts(from: fontName)
    self.fontSize = fontSize
    labelFonts = decodeFonts(from: labelFontName ?? fontName)
    self.labelFontSize = labelFontSize
    commentFonts = decodeFonts(from: commentFontName ?? fontName)
    self.commentFontSize = commentFontSize
  }
}

private extension SquirrelTheme {
  func combineFonts(_ fonts: [NSFont], size: CGFloat?) -> NSFont? {
    if fonts.count == 0 { return nil }
    if fonts.count == 1 {
      if let size = size {
        return fonts[0].withSize(size)
      } else {
        return fonts[0]
      }
    }
    let attribute = [NSFontDescriptor.AttributeName.cascadeList: fonts[1...].map { $0.fontDescriptor } ]
    let fontDescriptor = fonts[0].fontDescriptor.addingAttributes(attribute)
    return NSFont.init(descriptor: fontDescriptor, size: size ?? fonts[0].pointSize)
  }

  func decodeFonts(from fontString: String?) -> [NSFont] {
    guard let fontString = fontString else { return [] }
    var seenFontFamilies = Set<String>()
    let fontStrings = fontString.split(separator: ",")
    var fonts = [NSFont]()
    for string in fontStrings {
      if let matchedFontName = try? /^\s*(.+)-([^-]+)\s*$/.firstMatch(in: string) {
        let family = String(matchedFontName.output.1)
        let style = String(matchedFontName.output.2)
        if seenFontFamilies.contains(family) { continue }
        let fontDescriptor = NSFontDescriptor(fontAttributes: [.family: family, .face: style])
        if let font = NSFont(descriptor: fontDescriptor, size: Self.defaultFontSize) {
          fonts.append(font)
          seenFontFamilies.insert(family)
          continue
        }
      }
      let fontName = string.trimmingCharacters(in: .whitespaces)
      if seenFontFamilies.contains(fontName) { continue }
      let fontDescriptor = NSFontDescriptor(fontAttributes: [.name: fontName])
      if let font = NSFont(descriptor: fontDescriptor, size: Self.defaultFontSize) {
        fonts.append(font)
        seenFontFamilies.insert(fontName)
        continue
      }
    }
    return fonts
  }

  func blendColor(foregroundColor: NSColor, backgroundColor: NSColor?) -> NSColor {
    let foregroundColor = foregroundColor.usingColorSpace(NSColorSpace.deviceRGB)!
    let backgroundColor = (backgroundColor ?? NSColor.gray).usingColorSpace(NSColorSpace.deviceRGB)!
    func blend(foreground: CGFloat, background: CGFloat) -> CGFloat {
      return (foreground * 2 + background) / 3
    }
    return NSColor(deviceRed: blend(foreground: foregroundColor.redComponent, background: backgroundColor.redComponent),
                   green: blend(foreground: foregroundColor.greenComponent, background: backgroundColor.greenComponent),
                   blue: blend(foreground: foregroundColor.blueComponent, background: backgroundColor.blueComponent),
                   alpha: blend(foreground: foregroundColor.alphaComponent, background: backgroundColor.alphaComponent))
  }
}
