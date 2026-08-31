import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("Offline help catalog")
struct HelpContentTests {
    @Test("Help categories and article identifiers are unique")
    func catalogIdentifiersAreUnique() {
        let categories = HelpCatalog.categories
        let categoryIDs = categories.map(\.id)
        let articleIDs = categories.flatMap { $0.articles.map(\.id) }

        #expect(Set(categoryIDs).count == categoryIDs.count)
        #expect(Set(articleIDs).count == articleIDs.count)
        #expect(articleIDs.count >= 10)
    }

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
                #expect(Set(section.steps.map(\.id)).count == section.steps.count)
            }
        }
    }

    @Test("Quick-start help always covers the three product tools")
    func quickStartCoversCoreTools() throws {
        let quickStart = try #require(HelpCatalog.categories.first { $0.id == "quick-start" })
        let IDs = Set(quickStart.articles.map(\.id))

        #expect(IDs.isSuperset(of: ["overview", "media", "storage", "conversion"]))
    }

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

    @Test("Cleanup guidance includes an explicit review or privacy boundary")
    func cleanupGuidanceContainsSafetyNotices() {
        let articles = HelpCatalog.categories
            .flatMap(\.articles)
            .filter { !["overview", "faq"].contains($0.id) }

        #expect(articles.allSatisfy { $0.notice != nil })
        #expect(articles.contains { $0.id == "permissions-privacy" })
    }

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
