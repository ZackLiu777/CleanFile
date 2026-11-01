//
//  演示宿主应用如何通过导航容器打开图片转换界面。
//  示例依赖本地 ImageFormatConversionKit 包和 SwiftUI。
//  此入口仅展示集成方式，不实现文件导入或转换逻辑。
//  宿主需先将转换包加入依赖，再将此视图接入自身导航结构。
//  文件选择和后续处理由包提供的 ImageConversionView 及其依赖负责。
//

import ImageFormatConversionKit
import SwiftUI

/// Add the package as a local dependency, then route to this view from CleanMyIPhone.
/// 在导航容器中展示包提供的图片转换页面。
struct FormatConversionRoute: View {
    var body: some View {
        NavigationStack {
            ImageConversionView()
        }
    }
}
