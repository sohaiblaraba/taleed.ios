import Foundation
import Observation
import SwiftUI

/// "Membres bloqués" (screens.md §2 G16 item 10, slice C "Blocking"): `GET /me/blocks`, 50 a page, most
/// recent first, each row with "Débloquer" (`DELETE /members/{username}/block`, idempotent). The website
/// has no such page: the copy is the app's.
@MainActor
@Observable
final class BlockedMembersViewModel {
    enum Notice: Equatable {
        /// "@karim.h est débloqué."
        case unblocked(String)
        case error(ApiError)
    }

    let list: PagedList<BlockedMemberRow>
    private(set) var unblocking: Set<String> = []
    var notice: Notice?

    @ObservationIgnored private let api: BlocksApi

    init(api: BlocksApi) {
        self.api = api
        list = PagedList { cursor throws(ApiError) in try await api.blocks(cursor: cursor, automatic: false) }
    }

    /// The row leaves the list once the API answered.
    func unblock(_ member: BlockedMemberRow) async {
        guard let username = member.username, !unblocking.contains(member.id) else { return }
        unblocking.insert(member.id)
        defer { unblocking.remove(member.id) }
        do {
            try await api.unblock(username: username)
            list.remove(id: member.id)
            notice = .unblocked(member.displayName)
        } catch {
            notice = .error(error)
        }
    }
}

struct BlockedMembersView: View {
    @State private var model: BlockedMembersViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    init(api: BlocksApi) {
        _model = State(initialValue: BlockedMembersViewModel(api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.appSettingsBlockedTitle), onBack: { dismiss() })
        } content: {
            PagedListView(list: model.list) { members in
                LazyVStack(spacing: 0) {
                    ForEach(members) { member in
                        BlockedMemberRowView(member: member, isBusy: model.unblocking.contains(member.id),
                                             onOpen: { if let username = member.username { router.push(.member(username: username)) } },
                                             onUnblock: { Task { await model.unblock(member) } })
                    }
                }
            } empty: {
                // What blocking does, as the addresses' empty state explains them; `prohibit` as the
                // settings row (the shield is the trust pages').
                EmptyState(title: l10n.string(.appSettingsBlockedEmpty), message: l10n.string(.appSettingsBlockedEmptyBody),
                           icon: .prohibit)
                    .accessibilityIdentifier("blocked.empty")
            }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .unblocked(name): toasts.show(l10n.format(.appProfileUnblockedToast, name.isolatedByContent))
            case let .error(error): toasts.show(error: error)
            }
        }
    }
}

/// Avatar, the member's name and since when, then "Débloquer".
private struct BlockedMemberRowView: View {
    let member: BlockedMemberRow
    let isBusy: Bool
    let onOpen: () -> Void
    let onUnblock: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: TaleedSpacing.s12) {
                Button(action: onOpen) {
                    HStack(spacing: TaleedSpacing.s12) {
                        TaleedAvatar(initials: TaleedAvatar.initials(from: member.displayName), size: TaleedSize.avatarMd,
                                     imageURL: member.avatarURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: member.displayName.isolatedByContent)
                                .taleedFont(TaleedFont.bodyLarge)
                                .foregroundStyle(TaleedColor.textPrimary)
                                .lineLimit(1)
                            Text(l10n.format(.appSettingsBlockedSince,
                                             OrderText.date(member.blockedAt, locale: l10n.language.formattingLocale)))
                                .taleedFont(TaleedFont.bodySmall)
                                .foregroundStyle(TaleedColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(member.username == nil)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isLink)
                if member.username != nil {
                    TaleedButton(title: l10n.string(.appProfileUnblock), kind: .outline, size: .small, isLoading: isBusy,
                                 action: onUnblock)
                        .accessibilityLabel("\(l10n.string(.appProfileUnblock)) \(member.displayName)")
                        .accessibilityIdentifier("blocked.unblock.\(member.username ?? "")")
                }
            }
            .padding(.vertical, TaleedSpacing.s12)
            .padding(.horizontal, TaleedLayout.screenMargin)
            .frame(minHeight: 64)
            Rectangle()
                .fill(TaleedColor.borderSubtle)
                .frame(height: 1)
                .padding(.leading, TaleedLayout.screenMargin)
                .accessibilityHidden(true)
        }
    }
}
