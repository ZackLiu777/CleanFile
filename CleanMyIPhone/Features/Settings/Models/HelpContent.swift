//
//  HelpContent.swift
//  CleanMyIPhone
//
//  帮助中心的静态展示模型与内容目录。所有说明均可离线阅读，外链仅指向 Apple 支持。
//

import SwiftUI

/// 帮助首页的一个分组。
struct HelpCategory: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let articles: [HelpArticle]
}

/// 一篇帮助文章及其本地化内容。
struct HelpArticle: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let summary: LocalizedStringKey
    let systemImage: String
    let notice: HelpNotice?
    let sections: [HelpArticleSection]
    let resources: [HelpResource]
}

/// 文章中的一个独立主题，支持正文与有序步骤。
struct HelpArticleSection: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let paragraphs: [LocalizedStringKey]
    let steps: [HelpStep]

    init(
        id: String,
        title: LocalizedStringKey,
        paragraphs: [LocalizedStringKey],
        steps: [HelpStep] = []
    ) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs
        self.steps = steps
    }
}

/// 文章中的一个操作步骤。
struct HelpStep: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
}

/// 文章开头的边界、风险或隐私提醒。
struct HelpNotice {
    enum Tone {
        case information
        case caution
        case privacy
    }

    let tone: Tone
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
}

/// 可选的 Apple 官方延伸阅读。
struct HelpResource: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let urlString: String
}

/// 集中维护帮助内容，避免说明文字散落在多个 View 中。
enum HelpCatalog {
    static let categories: [HelpCategory] = [
        HelpCategory(
            id: "quick-start",
            title: "Quick Start",
            articles: [overview, media, storage, conversion]
        ),
        HelpCategory(
            id: "free-up-space",
            title: "Free Up iPhone Storage",
            articles: [storagePlan, photosCleanup, filesCleanup, appsCleanup, messagesAndSafari, systemData]
        ),
        HelpCategory(
            id: "questions",
            title: "Common Questions",
            articles: [frequentlyAskedQuestions]
        ),
        HelpCategory(
            id: "privacy",
            title: "Permissions & Privacy",
            articles: [permissionsAndPrivacy]
        )
    ]

    private static let overview = HelpArticle(
        id: "overview",
        title: "Meet the App",
        summary: "Understand the three tools and what each one can access.",
        systemImage: "square.grid.2x2",
        notice: HelpNotice(
            tone: .information,
            title: "Your choices stay in control",
            detail: "The app never deletes files automatically. You choose what to review and confirm every cleanup action."
        ),
        sections: [
            HelpArticleSection(
                id: "three-tools",
                title: "Three focused tools",
                paragraphs: [
                    "Media analyzes photos and videos that you allow through the Photos library. Storage analyzes only a folder you choose. Convert works with copies imported into the app's private workspace."
                ]
            ),
            HelpArticleSection(
                id: "access-boundary",
                title: "What the app cannot see",
                paragraphs: [
                    "iOS does not let one app browse another app's private files, system caches, or the entire iPhone file system. When a category is outside the app's access, Help shows the safe system path instead."
                ]
            ),
            HelpArticleSection(
                id: "good-order",
                title: "A practical order",
                paragraphs: [
                    "Check iPhone Storage first, then use Media or Storage for content the app can access. Use the system guides for apps, Messages, Safari, and System Data."
                ]
            )
        ],
        resources: []
    )

    private static let media = HelpArticle(
        id: "media",
        title: "Use Media",
        summary: "Review photos, similar items, screenshots, Live Photos, and videos.",
        systemImage: "photo.on.rectangle.angled",
        notice: HelpNotice(
            tone: .caution,
            title: "Similar does not mean identical",
            detail: "Similar-photo groups are review suggestions, not proof that files are exact duplicates. Keep the best shot before deleting anything."
        ),
        sections: [
            HelpArticleSection(
                id: "access",
                title: "Choose photo access",
                paragraphs: [
                    "Full Access lets Media analyze the whole library. Limited Access includes only the photos and videos you selected in the system permission sheet."
                ]
            ),
            HelpArticleSection(
                id: "workflow",
                title: "Analyze and review",
                paragraphs: [],
                steps: [
                    HelpStep(id: "open", title: "Open Media", detail: "Allow photo access, then wait for the library to load."),
                    HelpStep(id: "analyze", title: "Start analysis", detail: "Analyze the available library and let the app group useful cleanup candidates."),
                    HelpStep(id: "review", title: "Open a category", detail: "Preview items at full size and compare similar photos carefully."),
                    HelpStep(id: "delete", title: "Confirm your selection", detail: "Select only unwanted items and approve the Photos deletion request.")
                ]
            ),
            HelpArticleSection(
                id: "after-delete",
                title: "After deleting from Photos",
                paragraphs: [
                    "Deleted items move to Recently Deleted and may continue using storage until permanently removed. If iCloud Photos is enabled, deletion also syncs to your other devices."
                ]
            )
        ],
        resources: [
            HelpResource(id: "delete-photos", title: "Apple: Delete photos and videos", urlString: "https://support.apple.com/104967"),
            HelpResource(id: "icloud-photos", title: "Apple: Use iCloud Photos", urlString: "https://support.apple.com/108782")
        ]
    )

    private static let storage = HelpArticle(
        id: "storage",
        title: "Use Storage",
        summary: "Scan a folder you choose and explore its file distribution.",
        systemImage: "externaldrive",
        notice: HelpNotice(
            tone: .caution,
            title: "Review before deleting",
            detail: "Files deleted from an authorized folder may not be recoverable. The app cannot promise that they will appear in Recently Deleted."
        ),
        sections: [
            HelpArticleSection(
                id: "scope",
                title: "You choose the scan scope",
                paragraphs: [
                    "Storage can read only the folder you select in the system file picker. The analyzed total describes that folder, not all storage used by the iPhone."
                ]
            ),
            HelpArticleSection(
                id: "workflow",
                title: "Scan and explore",
                paragraphs: [],
                steps: [
                    HelpStep(id: "choose", title: "Choose a folder", detail: "Pick a folder in Files or a supported file provider."),
                    HelpStep(id: "scan", title: "Let the scan finish", detail: "The app reads file metadata and reports inaccessible or unavailable cloud items separately."),
                    HelpStep(id: "explore", title: "Explore the results", detail: "Use the folder map, categories, and detailed lists to find large files."),
                    HelpStep(id: "review", title: "Open before removing", detail: "Confirm the file and location, then delete only content you no longer need.")
                ]
            ),
            HelpArticleSection(
                id: "cloud-files",
                title: "Cloud files may be unavailable",
                paragraphs: [
                    "A file provider can keep content only in the cloud. If size or access is unavailable, download the file in Files and scan again."
                ]
            )
        ],
        resources: [
            HelpResource(id: "files", title: "Apple: Delete files or remove downloads", urlString: "https://support.apple.com/104953")
        ]
    )

    private static let conversion = HelpArticle(
        id: "conversion",
        title: "Use Convert",
        summary: "Convert images, videos, and audio without changing the original file.",
        systemImage: "arrow.triangle.2.circlepath",
        notice: HelpNotice(
            tone: .information,
            title: "The original stays where it was",
            detail: "Convert imports a working copy into the app. Clearing the conversion workspace removes app-managed copies and outputs, so export anything you want to keep first."
        ),
        sections: [
            HelpArticleSection(
                id: "workflow",
                title: "Convert a file",
                paragraphs: [],
                steps: [
                    HelpStep(id: "type", title: "Choose a conversion type", detail: "Open image, video, audio, or video-to-audio conversion."),
                    HelpStep(id: "import", title: "Import your files", detail: "Select supported items from Photos or Files and wait for the working copies to finish importing."),
                    HelpStep(id: "settings", title: "Review output settings", detail: "Choose the format and available size, quality, or metadata options."),
                    HelpStep(id: "convert", title: "Start conversion", detail: "Keep the task open until each item completes or reports an error."),
                    HelpStep(id: "export", title: "Save the result", detail: "Use the share action to save or send completed output before clearing the workspace.")
                ]
            ),
            HelpArticleSection(
                id: "storage",
                title: "Manage conversion storage",
                paragraphs: [
                    "Imported copies and converted outputs use space inside the app. Clear completed work when you no longer need it, after exporting any result you want to keep."
                ]
            )
        ],
        resources: []
    )

    private static let storagePlan = HelpArticle(
        id: "storage-plan",
        title: "Start with iPhone Storage",
        summary: "Find the largest category before deciding what to clean.",
        systemImage: "chart.bar",
        notice: HelpNotice(
            tone: .information,
            title: "Device storage is not iCloud storage",
            detail: "iPhone Storage measures space on this device. iCloud storage measures data kept in your iCloud account. Freeing one does not always free the other."
        ),
        sections: [
            HelpArticleSection(
                id: "check",
                title: "Build a cleanup plan",
                paragraphs: [],
                steps: [
                    HelpStep(id: "open", title: "Open iPhone Storage", detail: "Go to Settings > General > iPhone Storage and wait for the category chart to finish calculating."),
                    HelpStep(id: "largest", title: "Find the largest category", detail: "Start with Photos, apps, Messages, or downloads that can make a meaningful difference."),
                    HelpStep(id: "use-tool", title: "Use the right tool", detail: "Use Media for your authorized Photos library, Storage for a selected folder, and the system guide for everything else."),
                    HelpStep(id: "recheck", title: "Recheck after cleanup", detail: "Recently Deleted and system storage calculations can delay the visible change. Do not rely on a fixed update time.")
                ]
            ),
            HelpArticleSection(
                id: "comparison",
                title: "Why totals can differ",
                paragraphs: [
                    "The app reports only authorized content and can estimate some media sizes without downloading originals. The iPhone Storage total also includes apps, system data, caches, and content outside that scope."
                ]
            )
        ],
        resources: [
            HelpResource(id: "manage-storage", title: "Apple: Check storage on iPhone", urlString: "https://support.apple.com/guide/iphone/manage-storage-on-iphone/ios"),
            HelpResource(id: "storage-difference", title: "Apple: Device storage and iCloud storage", urlString: "https://support.apple.com/102670")
        ]
    )

    private static let photosCleanup = HelpArticle(
        id: "photos-cleanup",
        title: "Clean Up Photos & Videos",
        summary: "Review large videos, screenshots, and similar photos safely.",
        systemImage: "photo.on.rectangle",
        notice: HelpNotice(
            tone: .caution,
            title: "iCloud Photos syncs deletions",
            detail: "When iCloud Photos is on, deleting a photo or video removes it from other devices signed in to the same Apple Account."
        ),
        sections: [
            HelpArticleSection(
                id: "priorities",
                title: "Start with high-impact items",
                paragraphs: [
                    "Review long videos, 4K videos, screen recordings, and large screenshots first. Similar-photo groups can help you compare bursts or repeated shots, but you should choose the keeper yourself."
                ]
            ),
            HelpArticleSection(
                id: "icloud",
                title: "Understand optimized photos",
                paragraphs: [
                    "With Optimize iPhone Storage enabled, some originals remain in iCloud while smaller versions stay on the device. Media size can therefore be an estimate until the original is available."
                ]
            ),
            HelpArticleSection(
                id: "recently-deleted",
                title: "Finish only when you are certain",
                paragraphs: [
                    "Photos keeps deleted items in Recently Deleted for recovery. They can still occupy space until removed permanently, so empty that album only after confirming you no longer need the files."
                ]
            )
        ],
        resources: [
            HelpResource(id: "delete-photos", title: "Apple: Delete photos and videos", urlString: "https://support.apple.com/104967"),
            HelpResource(id: "icloud-photos", title: "Apple: Use iCloud Photos", urlString: "https://support.apple.com/108782")
        ]
    )

    private static let filesCleanup = HelpArticle(
        id: "files-cleanup",
        title: "Manage Files & iCloud Drive",
        summary: "Know when to remove a download and when to delete a file.",
        systemImage: "folder",
        notice: HelpNotice(
            tone: .caution,
            title: "Remove Download and Delete are different",
            detail: "Remove Download frees the local copy but keeps the file in iCloud Drive. Delete removes the file from iCloud Drive and synced devices."
        ),
        sections: [
            HelpArticleSection(
                id: "locations",
                title: "Check the file location",
                paragraphs: [
                    "In Files, confirm whether an item is under On My iPhone, iCloud Drive, or another provider. The same action can have different recovery and sync behavior in each location."
                ]
            ),
            HelpArticleSection(
                id: "local-copy",
                title: "Free space without deleting the cloud file",
                paragraphs: [
                    "For an iCloud Drive item, use Remove Download in Files when you only want to remove its local copy. The Storage tool does not replace this system action."
                ]
            ),
            HelpArticleSection(
                id: "direct-delete",
                title: "Use Storage deletion carefully",
                paragraphs: [
                    "Storage deletes a confirmed file inside the folder you authorized. Recovery depends on the location and file provider, and is not guaranteed."
                ]
            )
        ],
        resources: [
            HelpResource(id: "files", title: "Apple: Delete files or remove downloads", urlString: "https://support.apple.com/104953")
        ]
    )

    private static let appsCleanup = HelpArticle(
        id: "apps-cleanup",
        title: "Manage Apps & Downloads",
        summary: "Reduce app storage without expecting a universal cache cleaner.",
        systemImage: "square.grid.2x2",
        notice: HelpNotice(
            tone: .information,
            title: "The app cannot clear other apps' private data",
            detail: "iOS keeps each app's documents and caches private. Use iPhone Storage and the controls inside each app instead."
        ),
        sections: [
            HelpArticleSection(
                id: "offload",
                title: "Offload or delete",
                paragraphs: [
                    "In iPhone Storage, Offload App removes the app but keeps its documents and data. Delete App removes the app and its local data, so verify sync or backup before choosing it."
                ]
            ),
            HelpArticleSection(
                id: "downloads",
                title: "Remove offline downloads first",
                paragraphs: [
                    "Check downloaded music, podcasts, movies, maps, and other offline content inside the app that created it. Removing a download is often safer than deleting the account item or library entry."
                ]
            ),
            HelpArticleSection(
                id: "reinstall",
                title: "Be careful with reinstall advice",
                paragraphs: [
                    "Deleting and reinstalling can remove local-only data and login state. Use it only when the app's data is synced or backed up and its own cleanup controls are not enough."
                ]
            )
        ],
        resources: [
            HelpResource(id: "manage-storage", title: "Apple: Check storage on iPhone", urlString: "https://support.apple.com/guide/iphone/manage-storage-on-iphone/ios"),
            HelpResource(id: "music", title: "Apple: Remove music from iPhone", urlString: "https://support.apple.com/102344")
        ]
    )

    private static let messagesAndSafari = HelpArticle(
        id: "messages-safari",
        title: "Clean Up Messages & Safari",
        summary: "Use Apple's controls for attachments, history, and website data.",
        systemImage: "message",
        notice: HelpNotice(
            tone: .caution,
            title: "These actions happen outside the app",
            detail: "The app cannot read Messages or Safari data. Follow the system controls and review their sync and sign-in effects before deleting."
        ),
        sections: [
            HelpArticleSection(
                id: "messages",
                title: "Large Messages attachments",
                paragraphs: [
                    "Use iPhone Storage or the conversation details in Messages to review large attachments. With Messages in iCloud, deletion syncs across your devices; Recently Deleted can continue using space."
                ]
            ),
            HelpArticleSection(
                id: "safari",
                title: "Safari website data",
                paragraphs: [
                    "Use Settings > Apps > Safari to clear history and website data. This can close tabs or sign you out of websites, so save anything important first."
                ]
            )
        ],
        resources: [
            HelpResource(id: "messages", title: "Apple: Delete Messages and attachments", urlString: "https://support.apple.com/guide/iphone/delete-messages-and-attachments-iph2c9c4bfcb/ios"),
            HelpResource(id: "safari", title: "Apple: Clear Safari history and website data", urlString: "https://support.apple.com/105082")
        ]
    )

    private static let systemData = HelpArticle(
        id: "system-data",
        title: "Understand System Data",
        summary: "Learn why third-party cleaners cannot directly remove this category.",
        systemImage: "gearshape",
        notice: HelpNotice(
            tone: .information,
            title: "System Data is managed by iOS",
            detail: "The app cannot inspect or delete iOS caches, logs, updates, or other protected System Data. No third-party app has general access to that storage."
        ),
        sections: [
            HelpArticleSection(
                id: "changes",
                title: "Why the number changes",
                paragraphs: [
                    "System Data can include temporary files and resources that iOS creates and removes as needed. The total can change while the storage screen recalculates."
                ]
            ),
            HelpArticleSection(
                id: "safe-steps",
                title: "Safe steps to try",
                paragraphs: [
                    "Install the latest iOS update, restart the iPhone, review Safari data and offline downloads, then let iPhone Storage recalculate. If an unusually large total persists, contact Apple Support."
                ]
            ),
            HelpArticleSection(
                id: "avoid",
                title: "Avoid risky shortcuts",
                paragraphs: [
                    "Do not install profiles, grant unknown computer access, or erase the iPhone for a promised one-tap cache cleanup. Back up important data before any system reset."
                ]
            )
        ],
        resources: [
            HelpResource(id: "manage-storage", title: "Apple: Check storage on iPhone", urlString: "https://support.apple.com/guide/iphone/manage-storage-on-iphone/ios")
        ]
    )

    private static let frequentlyAskedQuestions = HelpArticle(
        id: "faq",
        title: "Frequently Asked Questions",
        summary: "Clear answers about scope, estimates, iCloud, deletion, and recovery.",
        systemImage: "questionmark.bubble",
        notice: nil,
        sections: [
            HelpArticleSection(
                id: "whole-iphone",
                title: "Can the app scan my whole iPhone?",
                paragraphs: [
                    "No. It can analyze the Photos items you authorize, the folder you choose, and its own conversion workspace. Other apps and protected system storage remain private."
                ]
            ),
            HelpArticleSection(
                id: "different-total",
                title: "Why is the analyzed size different from iPhone Storage?",
                paragraphs: [
                    "The scope is different. iPhone Storage includes apps and system data, while this app reports authorized content and may estimate media sizes when originals are in iCloud."
                ]
            ),
            HelpArticleSection(
                id: "limited-access",
                title: "What happens with Limited Photos Access?",
                paragraphs: [
                    "Only the items selected in the system permission sheet are available. Counts, groups, and recommendations cannot include the rest of the library."
                ]
            ),
            HelpArticleSection(
                id: "similar",
                title: "Are similar photos exact duplicates?",
                paragraphs: [
                    "Not necessarily. They are visually related candidates and can include different frames, edits, or resolutions. Always compare them before selecting one to remove."
                ]
            ),
            HelpArticleSection(
                id: "cloud-unavailable",
                title: "Why was an iCloud file skipped?",
                paragraphs: [
                    "The original may not be downloaded, the provider may be offline, or permission may have changed. Download it in the owning app or Files, then try again."
                ]
            ),
            HelpArticleSection(
                id: "space-delay",
                title: "Why did free space not update immediately?",
                paragraphs: [
                    "Deleted content may remain in Recently Deleted, and iOS storage totals can take time to recalculate. Check the relevant Recently Deleted location, then recheck iPhone Storage later."
                ]
            ),
            HelpArticleSection(
                id: "recovery",
                title: "Can I recover something I deleted?",
                paragraphs: [
                    "Photos and some Files locations may offer Recently Deleted. A file removed through Storage may not be recoverable, so preview important items and keep a backup before deletion."
                ]
            ),
            HelpArticleSection(
                id: "uploads",
                title: "Does analysis or conversion upload my files?",
                paragraphs: [
                    "No. Media analysis, folder analysis, and conversion run on this device. Apple services or file providers may sync their own content according to your existing settings."
                ]
            )
        ],
        resources: []
    )

    private static let permissionsAndPrivacy = HelpArticle(
        id: "permissions-privacy",
        title: "Permissions & Privacy",
        summary: "See why each permission is needed and how your files are protected.",
        systemImage: "lock.shield",
        notice: HelpNotice(
            tone: .privacy,
            title: "Local by design",
            detail: "Media analysis, folder scanning, and conversion happen on this device. The app does not upload your files for these features."
        ),
        sections: [
            HelpArticleSection(
                id: "photos",
                title: "Photos permission",
                paragraphs: [
                    "Media needs Photos access to display and analyze library items. You can choose Full Access, Limited Access, or no access, and change the choice later in System Settings."
                ]
            ),
            HelpArticleSection(
                id: "folders",
                title: "Folder permission",
                paragraphs: [
                    "Storage asks you to choose a folder because iOS does not grant automatic access to all files. Access can expire or change when a file provider becomes unavailable."
                ]
            ),
            HelpArticleSection(
                id: "conversion",
                title: "Conversion workspace",
                paragraphs: [
                    "Convert keeps imported working copies and outputs inside app-managed storage. The original outside the app is not replaced. Clear the workspace only after exporting results you want to keep."
                ]
            ),
            HelpArticleSection(
                id: "deletion",
                title: "Deletion stays user controlled",
                paragraphs: [
                    "Scanning and analysis never delete content. Removal begins only after you select items and confirm the action."
                ]
            )
        ],
        resources: [
            HelpResource(id: "privacy-controls", title: "Apple: Control access to information in apps", urlString: "https://support.apple.com/guide/iphone/control-access-to-information-in-apps-iph251e92810/ios")
        ]
    )
}
