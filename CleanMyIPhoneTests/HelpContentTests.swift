//
//  离线帮助内容契约
//
//  检查帮助目录标识、文章结构、操作步骤和支持链接。
//  同时确认清理说明包含审核或隐私边界。
//  检查目录、文章和步骤标识唯一且内容非空，并要求外部资源指向 Apple Support。
//  直接检查应用内静态帮助目录，不打开外部链接或使用用户数据。
//

import Foundation
import Testing
@testable import CleanMyIPhone

/// 验证离线帮助目录与文章内容的基本完整性和安全边界。
@Suite("Offline help catalog")
struct HelpContentTests {
    /// 检查分类与文章标识不重复，并确认目录包含足够的文章。
    @Test("Help categories and article identifiers are unique")
    func catalogIdentifiersAreUnique() {
        let categories = HelpCatalog.categories
        let categoryIDs = categories.map(\.id)
        let articleIDs = categories.flatMap { $0.articles.map(\.id) }

        #expect(Set(categoryIDs).count == categoryIDs.count)
        #expect(Set(articleIDs).count == articleIDs.count)
        #expect(articleIDs.count >= 10)
    }

    /// 逐篇检查图标、章节内容和章节及步骤标识，避免出现无法呈现的空结构。
    @Test("Every article has readable structure and a stable icon")
    func everyArticleHasContent() {
        for article in HelpCatalog.categories.flatMap(\.articles) {
            #expect(!article.id.isEmpty)
            #expect(!article.systemImage.isEmpty)
            #expect(!article.sections.isEmpty)

            let sectionIDs = article.sections.map(\.id)
            #expect(Set(sectionIDs).count == sectionIDs.count)
            for section in article.sections {
                #expect(!section.id.isEmpty)
                #expect(!section.paragraphs.isEmpty || !section.steps.isEmpty)
                #expect(Set(section.steps.map { $0.id }).count == section.steps.count)
            }
        }
    }

    /// 检查快速入门保留概览、媒体、存储和转换四个入口。
    @Test("Quick-start help always covers the three product tools")
    func quickStartCoversCoreTools() throws {
        let quickStart = try #require(HelpCatalog.categories.first { $0.id == "quick-start" })
        let IDs = Set(quickStart.articles.map(\.id))

        #expect(IDs.isSuperset(of: ["overview", "media", "storage", "conversion"]))
    }

    /// 外部资源必须使用 HTTPS 且指向 Apple Support，避免帮助内容链接到意外来源。
    @Test("Articles with external resources link only to HTTPS Apple Support")
    func resourcesStayOnAppleSupport() throws {
        let resources = HelpCatalog.categories.flatMap { $0.articles }.flatMap(\.resources)
        #expect(!resources.isEmpty)

        for resource in resources {
            let url = try #require(URL(string: resource.urlString))
            #expect(url.scheme == "https")
            #expect(url.host == "support.apple.com")
            #expect(!url.path.isEmpty)
        }
    }

    /// 清理相关说明应包含审核或隐私边界，提醒用户理解操作。
    @Test("Cleanup guidance includes an explicit review or privacy boundary")
    func cleanupGuidanceContainsSafetyNotices() {
        let articles = HelpCatalog.categories
            .flatMap(\.articles)
            .filter { !["overview", "faq"].contains($0.id) }

        #expect(articles.allSatisfy { $0.notice != nil })
        #expect(articles.contains { $0.id == "permissions-privacy" })
    }

    /// 确认至少四篇文章包含操作步骤，且各步骤都有非空标识。
    @Test("Workflow articles expose actionable ordered steps")
    func workflowArticlesHaveOrderedSteps() {
        let workflowArticles = HelpCatalog.categories
            .flatMap(\.articles)
            .filter { article in
                article.sections.contains { !$0.steps.isEmpty }
            }

        #expect(workflowArticles.count >= 4)
        for article in workflowArticles {
            let steps = article.sections.flatMap(\.steps)
            #expect(steps.allSatisfy { !$0.id.isEmpty })
        }
    }
}
