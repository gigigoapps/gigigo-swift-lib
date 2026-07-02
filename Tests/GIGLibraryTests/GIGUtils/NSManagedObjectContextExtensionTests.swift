//
//  NSManagedObjectContextExtensionTests.swift
//  GIGLibraryTests
//
//  Covers the Core Data helpers on `NSManagedObjectContext` (C014/C044):
//  queue-safe execution via `performAndWait`, real error propagation, and
//  `NSPredicate`-based filtering.
//

import Testing
import CoreData
@testable import GIGLibrary

// `.serialized`: each test spins up a Core Data stack whose model registers the `Item` entity
// against the generic `NSManagedObject` class. Core Data keeps process-global entity↔class
// registration state that is not safe to build concurrently, so these must not run in parallel.
@Suite("NSManagedObjectContext helpers", .serialized)
struct NSManagedObjectContextExtensionTests {

	/// Builds an in-memory Core Data stack with a single `Item { name: String }` entity.
	private func makeContext() throws -> NSManagedObjectContext {
		let model = NSManagedObjectModel()

		let entity = NSEntityDescription()
		entity.name = "Item"
		entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

		let nameAttr = NSAttributeDescription()
		nameAttr.name = "name"
		nameAttr.attributeType = .stringAttributeType
		nameAttr.isOptional = true
		entity.properties = [nameAttr]

		model.entities = [entity]

		let container = NSPersistentContainer(name: "TestModel", managedObjectModel: model)
		let description = NSPersistentStoreDescription()
		description.type = NSInMemoryStoreType
		container.persistentStoreDescriptions = [description]

		var loadError: Error?
		container.loadPersistentStores { _, error in loadError = error }
		if let loadError { throw loadError }

		return container.viewContext
	}

	@Test("Given a known entity name, createEntity inserts an object")
	func createEntityInsertsObject() throws {
		let context = try makeContext()

		let object = context.createEntity("Item")

		#expect(object != nil)
		#expect(object?.entity.name == "Item")
	}

	@Test("Given an unknown entity name, createEntity returns nil")
	func createEntityUnknownReturnsNil() throws {
		let context = try makeContext()
		#expect(context.createEntity("DoesNotExist") == nil)
	}

	@Test("Given inserted objects, fetchList returns all of them")
	func fetchListReturnsAll() throws {
		let context = try makeContext()
		context.createEntity("Item")?.setValue("a", forKey: "name")
		context.createEntity("Item")?.setValue("b", forKey: "name")

		let results = try context.fetchList("Item")
		#expect(results.count == 2)
	}

	@Test("Given a predicate, fetchList filters results")
	func fetchListFiltersByPredicate() throws {
		let context = try makeContext()
		context.createEntity("Item")?.setValue("keep", forKey: "name")
		context.createEntity("Item")?.setValue("drop", forKey: "name")

		let results = try context.fetchList("Item", predicate: NSPredicate(format: "name == %@", "keep"))
		#expect(results.count == 1)
		#expect(results.first?.value(forKey: "name") as? String == "keep")
	}

	@Test("Given a matching predicate, fetchFirst returns the object")
	func fetchFirstReturnsMatch() throws {
		let context = try makeContext()
		context.createEntity("Item")?.setValue("target", forKey: "name")

		let object = try context.fetchFirst("Item", predicate: NSPredicate(format: "name == %@", "target"))
		#expect(object?.value(forKey: "name") as? String == "target")
	}

	@Test("Given no matching objects, fetchFirst returns nil")
	func fetchFirstNoMatchReturnsNil() throws {
		let context = try makeContext()
		context.createEntity("Item")?.setValue("other", forKey: "name")

		let object = try context.fetchFirst("Item", predicate: NSPredicate(format: "name == %@", "missing"))
		#expect(object == nil)
	}
}
