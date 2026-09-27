import Foundation
import SwiftData
import FamiloqCore
import FamiloqBudget

/// Budget-module queries. Every query is still scoped to `familyID`.
extension FamilyRepository {
    // MARK: Categories

    func categories(includeArchived: Bool = false) throws -> [ExpenseCategory] {
        let fid = familyID
        let descriptor = FetchDescriptor<ExpenseCategory>(
            predicate: #Predicate<ExpenseCategory> { $0.familyID == fid },
            sortBy: [SortDescriptor(\ExpenseCategory.sortOrder)]
        )
        let all = try context.fetch(descriptor)
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    func subcategories(includeArchived: Bool = false) throws -> [ExpenseSubcategory] {
        let fid = familyID
        let descriptor = FetchDescriptor<ExpenseSubcategory>(
            predicate: #Predicate<ExpenseSubcategory> { $0.familyID == fid },
            sortBy: [SortDescriptor(\ExpenseSubcategory.sortOrder)]
        )
        let all = try context.fetch(descriptor)
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    // MARK: Expenses

    func expenses(from start: Date, to end: Date) throws -> [Expense] {
        let fid = familyID
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { $0.familyID == fid && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\Expense.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func allExpenses() throws -> [Expense] {
        let fid = familyID
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { $0.familyID == fid },
            sortBy: [SortDescriptor(\Expense.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func expensesNeedingConversion() throws -> [Expense] {
        let fid = familyID
        let pending = ConversionStatus.pending.rawValue
        let estimated = ConversionStatus.estimated.rawValue
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> {
                $0.familyID == fid && ($0.conversionStatusRaw == pending || $0.conversionStatusRaw == estimated)
            }
        )
        return try context.fetch(descriptor)
    }

    /// Inserts an expense after verifying it belongs to this family.
    func insert(_ expense: Expense) throws {
        guard expense.familyID == familyID else { throw RepositoryError.wrongFamily }
        context.insert(expense)
    }

    // MARK: Budgets & rules

    func budgets() throws -> [Budget] {
        let fid = familyID
        let descriptor = FetchDescriptor<Budget>(predicate: #Predicate<Budget> { $0.familyID == fid })
        return try context.fetch(descriptor)
    }

    func merchantRules() throws -> [MerchantRuleRecord] {
        let fid = familyID
        let descriptor = FetchDescriptor<MerchantRuleRecord>(predicate: #Predicate<MerchantRuleRecord> { $0.familyID == fid })
        return try context.fetch(descriptor)
    }
}
