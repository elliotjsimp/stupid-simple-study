import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class TermContext {
    private(set) var activeTerm: Term?
    private(set) var displayedTerm: Term?
    private(set) var allTerms: [Term] = []

    var canStartLiveSession: Bool {
        guard let activeTerm, let displayedTerm else { return false }
        return activeTerm.persistentModelID == displayedTerm.persistentModelID
    }

    var isBrowsingNonActiveTerm: Bool {
        guard let activeTerm, let displayedTerm else { return false }
        return activeTerm.persistentModelID != displayedTerm.persistentModelID
    }

    var isDisplayedTermConcluded: Bool {
        guard let displayedTerm else { return false }
        return displayedTerm.lastDay < Date().startOfDay
    }

    func refresh(terms: [Term], preferredActive: Term? = nil) {
        allTerms = terms.sorted { $0.firstDay < $1.firstDay }
        let today = Date().startOfDay

        if let preferredActive {
            activeTerm = preferredActive
        } else if let matching = allTerms.first(where: { $0.contains(date: today) }) {
            activeTerm = matching
        } else {
            activeTerm = allTerms.last
        }

        if displayedTerm == nil || !allTerms.contains(where: { $0.persistentModelID == displayedTerm?.persistentModelID }) {
            displayedTerm = activeTerm ?? allTerms.last
        }
    }

    func selectDisplayedTerm(_ term: Term) {
        displayedTerm = term
    }

    func navigateTerm(forward: Bool) {
        guard let displayedTerm,
              let index = allTerms.firstIndex(where: { $0.persistentModelID == displayedTerm.persistentModelID })
        else { return }
        let nextIndex = forward ? index + 1 : index - 1
        guard allTerms.indices.contains(nextIndex) else { return }
        self.displayedTerm = allTerms[nextIndex]
    }

    var canNavigateBackward: Bool {
        guard let displayedTerm,
              let index = allTerms.firstIndex(where: { $0.persistentModelID == displayedTerm.persistentModelID })
        else { return false }
        return index > 0
    }

    var canNavigateForward: Bool {
        guard let displayedTerm,
              let index = allTerms.firstIndex(where: { $0.persistentModelID == displayedTerm.persistentModelID })
        else { return false }
        return index < allTerms.count - 1
    }

    func validateNoOverlap(for term: Term, excluding: Term? = nil) -> Bool {
        for existing in allTerms {
            if let excluding, existing.persistentModelID == excluding.persistentModelID { continue }
            if term.overlaps(with: existing) { return false }
        }
        return true
    }

    func courseNameExistsInHistory(_ name: String, in context: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let descriptor = FetchDescriptor<Course>()
        let courses = (try? context.fetch(descriptor)) ?? []
        return courses.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

private struct TermContextKey: EnvironmentKey {
    static let defaultValue = TermContext()
}

extension EnvironmentValues {
    var termContext: TermContext {
        get { self[TermContextKey.self] }
        set { self[TermContextKey.self] = newValue }
    }
}
