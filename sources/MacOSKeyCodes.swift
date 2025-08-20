//
//  MacOSKeyCodes.swift
//  Squirrel（松鼠输入法）
//
//  Created by Leo Liu on 5/9/24.
//

// 引入 Carbon 框架，这是 macOS 系统的底层框架，用来处理键盘、鼠标等硬件输入
// 就像是电脑的"神经系统"，负责接收键盘的信号
import Carbon
// 引入 AppKit 框架，这是 macOS 应用程序的基础框架
// 就像是房子的"地基"，为应用程序提供基本功能
import AppKit

// 定义一个结构体，专门用来处理键盘按键的转换
// 就像一个"翻译官"，负责把 macOS 的键盘语言翻译成 Rime 输入法能听懂的语言
struct SquirrelKeycode {

  // 这个函数用来转换修饰键的状态
// 修饰键就是那些需要和其他键一起按的键，比如 Shift、Command、Option 等
// 就像是翻译员，把 macOS 的修饰键语言翻译成 Rime 输入法能懂的语言
  static func osxModifiersToRime(modifiers: NSEvent.ModifierFlags) -> UInt32 {
    // 创建一个变量来存储转换后的结果，初始值为 0
    // 就像一个空盒子，准备装翻译好的东西
    var ret: UInt32 = 0
    
    // 检查是否按下了大写锁定键（Caps Lock）
    if modifiers.contains(.capsLock) {
      // 如果按下了，就在结果中标记"大写锁定"状态
      // |= 这个符号就像是给盒子添加标记
      ret |= kLockMask.rawValue
    }
    
    // 检查是否按下了 Shift 键
    if modifiers.contains(.shift) {
      // 如果按下了，就在结果中标记"Shift"状态
      ret |= kShiftMask.rawValue
    }
    
    // 检查是否按下了 Control 键
    if modifiers.contains(.control) {
      // 如果按下了，就在结果中标记"Control"状态
      ret |= kControlMask.rawValue
    }
    
    // 检查是否按下了 Option 键（也叫 Alt 键）
    if modifiers.contains(.option) {
      // 如果按下了，就在结果中标记"Alt"状态
      ret |= kAltMask.rawValue
    }
    
    // 检查是否按下了 Command 键（macOS 的特色键，有 ⌘ 符号）
    if modifiers.contains(.command) {
      // 如果按下了，就在结果中标记"Super"状态（在 Linux 系统中叫 Super 键）
      ret |= kSuperMask.rawValue
    }
    
    // 返回转换后的结果
    return ret
  }

  // 这个函数用来转换普通按键的编码
// 把 macOS 系统的按键编码转换成 Rime 输入法能理解的编码
// 就像把方言翻译成普通话，让不同系统能够互相理解
  static func osxKeycodeToRime(keycode: UInt16, keychar: Character?, shift: Bool, caps: Bool) -> UInt32 {
    // 首先检查这个按键是否在预定义的按键映射表中
    // keycodeMappings 就是一本字典，记录了 macOS 按键和 Rime 按键的对应关系
    if let code = keycodeMappings[Int(keycode)] {
      // 如果找到了对应的翻译，就直接返回翻译结果
      return UInt32(code)
    }

    // 如果在预定义表中没找到，就尝试通过字符来识别按键
    // keychar 就是用户实际输入的那个字符，比如 'a'、'1'、'$' 等
    if let keychar = keychar, keychar.isASCII, let codeValue = keychar.unicodeScalars.first?.value {
      // 注意：IBus/Rime 系统对大小写字母使用不同的按键编码
      // NOTE: IBus/Rime use different keycodes for uppercase/lowercase letters.
      
      // 如果是小写字母，并且 Shift 和 Caps Lock 的状态不一致
      // （比如按了 Shift 但没开 Caps Lock，或者开了 Caps Lock 但没按 Shift）
      if keychar.isLowercase && (shift != caps) {
        // 就需要把小写字母转换成大写字母
        // lowercase -> Uppercase
        return keychar.uppercased().unicodeScalars.first!.value
      }

      // 根据字符的 Unicode 编码值来处理特殊字符
      switch codeValue {
      case 0x20...0x7e:
        // 如果是标准的 ASCII 字符（空格到波浪号），直接返回
        return codeValue
      case 0x1b:
        // ASCII 码 27（Escape 键）在某些情况下对应左方括号
        return UInt32(XK_bracketleft)
      case 0x1c:
        // ASCII 码 28 对应反斜杠
        return UInt32(XK_backslash)
      case 0x1d:
        // ASCII 码 29 对应右方括号
        return UInt32(XK_bracketright)
      case 0x1f:
        // ASCII 码 31 对应减号
        return UInt32(XK_minus)
      default:
        // 如果都不匹配，就跳过
        break
      }
    }

    // 如果上述方法都没找到合适的翻译，就检查额外的映射表
    // additionalCodeMappings 是补充字典，包含一些额外的按键对应关系
    if let code = additionalCodeMappings[Int(keycode)] {
      return UInt32(code)
    }

    // 如果所有方法都找不到对应的按键，就返回"无效按键"的标记
    // 就像查字典没找到这个词，就标记为"未知词汇"
    return UInt32(XK_VoidSymbol)
  }

  // 创建一个私有的按键映射字典
// 这个字典就像一本翻译手册，把 macOS 的按键编码翻译成 Rime 能懂的编码
// private 意味着只有这个文件里的代码能使用这个字典
  private static let keycodeMappings: [Int: Int32] = [
    // 修饰键（modifier keys）- 这些是需要和其他键一起按的键
    kVK_CapsLock: XK_Caps_Lock,        // 大写锁定键
    kVK_Command: XK_Super_L,           // 左 Command 键（macOS 的 ⌘ 键）
    kVK_RightCommand: XK_Super_R,      // 右 Command 键
    kVK_Control: XK_Control_L,         // 左 Control 键
    kVK_RightControl: XK_Control_R,    // 右 Control 键
    kVK_Function: XK_Hyper_L,          // 功能键（fn 键）
    kVK_Option: XK_Alt_L,              // 左 Option 键（也叫 Alt 键）
    kVK_RightOption: XK_Alt_R,         // 右 Option 键
    kVK_Shift: XK_Shift_L,             // 左 Shift 键
    kVK_RightShift: XK_Shift_R,        // 右 Shift 键

    // 特殊按键（special keys）- 这些是功能独立的按键
    kVK_Delete: XK_BackSpace,          // 删除键（退格键）
    kVK_Escape: XK_Escape,             // ESC 键（退出键）
    kVK_ForwardDelete: XK_Delete,      // 向前删除键
    kVK_Help: XK_Help,                 // 帮助键
    kVK_Return: XK_Return,             // 回车键
    kVK_Space: XK_space,               // 空格键
    kVK_Tab: XK_Tab,                   // Tab 键（制表键）

    // 功能键（function keys）- 键盘顶部的 F1-F20 键
    kVK_F1: XK_F1,                     // F1 键
    kVK_F2: XK_F2,                     // F2 键
    kVK_F3: XK_F3,                     // F3 键
    kVK_F4: XK_F4,                     // F4 键
    kVK_F5: XK_F5,                     // F5 键
    kVK_F6: XK_F6,                     // F6 键
    kVK_F7: XK_F7,                     // F7 键
    kVK_F8: XK_F8,                     // F8 键
    kVK_F9: XK_F9,                     // F9 键
    kVK_F10: XK_F10,                   // F10 键
    kVK_F11: XK_F11,                   // F11 键
    kVK_F12: XK_F12,                   // F12 键
    kVK_F13: XK_F13,                   // F13 键
    kVK_F14: XK_F14,                   // F14 键
    kVK_F15: XK_F15,                   // F15 键
    kVK_F16: XK_F16,                   // F16 键
    kVK_F17: XK_F17,                   // F17 键
    kVK_F18: XK_F18,                   // F18 键
    kVK_F19: XK_F19,                   // F19 键
    kVK_F20: XK_F20,                   // F20 键

    // 光标键（cursor keys）- 控制光标移动的按键
    kVK_UpArrow: XK_Up,                // 向上箭头键
    kVK_DownArrow: XK_Down,            // 向下箭头键
    kVK_LeftArrow: XK_Left,            // 向左箭头键
    kVK_RightArrow: XK_Right,          // 向右箭头键
    kVK_PageUp: XK_Page_Up,            // 向上翻页键
    kVK_PageDown: XK_Page_Down,        // 向下翻页键
    kVK_Home: XK_Home,                 // Home 键（移到行首）
    kVK_End: XK_End,                   // End 键（移到行尾）

    // 小键盘（keypad）- 键盘右侧的数字键盘区域
    kVK_ANSI_Keypad0: XK_KP_0,        // 小键盘 0
    kVK_ANSI_Keypad1: XK_KP_1,        // 小键盘 1
    kVK_ANSI_Keypad2: XK_KP_2,        // 小键盘 2
    kVK_ANSI_Keypad3: XK_KP_3,        // 小键盘 3
    kVK_ANSI_Keypad4: XK_KP_4,        // 小键盘 4
    kVK_ANSI_Keypad5: XK_KP_5,        // 小键盘 5
    kVK_ANSI_Keypad6: XK_KP_6,        // 小键盘 6
    kVK_ANSI_Keypad7: XK_KP_7,        // 小键盘 7
    kVK_ANSI_Keypad8: XK_KP_8,        // 小键盘 8
    kVK_ANSI_Keypad9: XK_KP_9,        // 小键盘 9
    kVK_ANSI_KeypadClear: XK_Clear,   // 小键盘清除键
    kVK_ANSI_KeypadDecimal: XK_KP_Decimal,  // 小键盘小数点
    kVK_ANSI_KeypadEquals: XK_KP_Equal,     // 小键盘等号
    kVK_ANSI_KeypadMinus: XK_KP_Subtract,  // 小键盘减号
    kVK_ANSI_KeypadMultiply: XK_KP_Multiply, // 小键盘乘号
    kVK_ANSI_KeypadPlus: XK_KP_Add,        // 小键盘加号
    kVK_ANSI_KeypadDivide: XK_KP_Divide,   // 小键盘除号
    kVK_ANSI_KeypadEnter: XK_KP_Enter,     // 小键盘回车键

    // 其他特殊按键（主要针对日本键盘等特殊键盘布局）
    kVK_ISO_Section: XK_section,       // ISO 段落符号键
    kVK_JIS_Yen: XK_yen,               // 日文键盘的日元符号键
    kVK_JIS_Underscore: XK_underscore, // 日文键盘的下划线键
    kVK_JIS_KeypadComma: XK_comma,     // 日文键盘的小键盘逗号
    kVK_JIS_Eisu: XK_Eisu_Shift,       // 日文键盘的英数切换键
    kVK_JIS_Kana: XK_Kana_Shift        // 日文键盘的假名切换键
  ]

  // 创建一个补充的按键映射字典
// 这个字典是主字典的补充，包含一些额外的按键对应关系
// 就像主词典的附录，收录了一些额外的词汇
  private static let additionalCodeMappings: [Int: Int32] = [
    // 数字键（number keys）- 键盘上方的数字键 0-9
    kVK_ANSI_0: XK_0,                  // 数字键 0
    kVK_ANSI_1: XK_1,                  // 数字键 1
    kVK_ANSI_2: XK_2,                  // 数字键 2
    kVK_ANSI_3: XK_3,                  // 数字键 3
    kVK_ANSI_4: XK_4,                  // 数字键 4
    kVK_ANSI_5: XK_5,                  // 数字键 5
    kVK_ANSI_6: XK_6,                  // 数字键 6
    kVK_ANSI_7: XK_7,                  // 数字键 7
    kVK_ANSI_8: XK_8,                  // 数字键 8
    kVK_ANSI_9: XK_9,                  // 数字键 9

    // 标点符号键（punctuation keys）- 各种标点符号
    kVK_ANSI_RightBracket: XK_bracketright,  // 右方括号 ]
    kVK_ANSI_LeftBracket: XK_bracketleft,    // 左方括号 [
    kVK_ANSI_Comma: XK_comma,                // 逗号 ,
    kVK_ANSI_Grave: XK_grave,                // 反引号 `（在数字键 1 的左边）
    kVK_ANSI_Period: XK_period,              // 句号 .
    // 音量键（volume keys）- 这里被注释掉了，暂时不使用
    // kVK_VolumeUp:                          // 音量增大键
    // kVK_VolumeDown:                        // 音量减小键
    // kVK_Mute:                              // 静音键
    kVK_ANSI_Semicolon: XK_semicolon,        // 分号 ;
    kVK_ANSI_Quote: XK_apostrophe,           // 单引号 '
    kVK_ANSI_Backslash: XK_backslash,        // 反斜杠 \
    kVK_ANSI_Minus: XK_minus,                 // 减号 -
    kVK_ANSI_Slash: XK_slash,                // 斜杠 /
    kVK_ANSI_Equal: XK_equal,                 // 等号 =

    // 字母键（letter keys）- 英文字母 A-Z
    kVK_ANSI_A: XK_a,                  // 字母 A
    kVK_ANSI_B: XK_b,                  // 字母 B
    kVK_ANSI_C: XK_c,                  // 字母 C
    kVK_ANSI_D: XK_d,                  // 字母 D
    kVK_ANSI_E: XK_e,                  // 字母 E
    kVK_ANSI_F: XK_f,                  // 字母 F
    kVK_ANSI_G: XK_g,                  // 字母 G
    kVK_ANSI_H: XK_h,                  // 字母 H
    kVK_ANSI_I: XK_i,                  // 字母 I
    kVK_ANSI_J: XK_j,                  // 字母 J
    kVK_ANSI_K: XK_k,                  // 字母 K
    kVK_ANSI_L: XK_l,                  // 字母 L
    kVK_ANSI_M: XK_m,                  // 字母 M
    kVK_ANSI_N: XK_n,                  // 字母 N
    kVK_ANSI_O: XK_o,                  // 字母 O
    kVK_ANSI_P: XK_p,                  // 字母 P
    kVK_ANSI_Q: XK_q,                  // 字母 Q
    kVK_ANSI_R: XK_r,                  // 字母 R
    kVK_ANSI_S: XK_s,                  // 字母 S
    kVK_ANSI_T: XK_t,                  // 字母 T
    kVK_ANSI_U: XK_u,                  // 字母 U
    kVK_ANSI_V: XK_v,                  // 字母 V
    kVK_ANSI_W: XK_w,                  // 字母 W
    kVK_ANSI_X: XK_x,                  // 字母 X
    kVK_ANSI_Y: XK_y,                  // 字母 Y
    kVK_ANSI_Z: XK_z                   // 字母 Z
  ]
}
