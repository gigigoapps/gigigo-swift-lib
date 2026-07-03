//
//  NSManagedObjectContext+Extension.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 14/3/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import CoreData

public extension NSManagedObjectContext {

	/// Inserts a new managed object for `name`. The insertion runs on the context's own queue via
	/// `performAndWait`, but the returned `NSManagedObject` is confined to that queue: read or
	/// mutate it only on the context's queue (e.g. inside `context.perform`/`performAndWait`, or on
	/// the main thread for a main-queue context). Returns `nil` if the entity name is unknown.
    func createEntity(_ name: String) -> NSManagedObject? {
		self.performAndWait {
			guard let entity = NSEntityDescription.entity(forEntityName: name, in: self) else {
				return nil
			}

			return NSManagedObject(entity: entity, insertInto: self)
		}
	}

	/// Fetches the first object of `entityName` matching `predicate` (all objects if `nil`). The
	/// fetch runs on the context's queue and propagates any underlying Core Data error instead of
	/// swallowing it. The returned object is confined to the context's queue — use it only on that
	/// queue. The `predicate` is a pre-built `NSPredicate`, so callers cannot inject an unbound
	/// format string.
    func fetchFirst(_ entityName: String, predicate: NSPredicate? = nil) throws -> NSManagedObject? {
		// `NSPredicate` is not `Sendable`, but it is only read synchronously on the context's own
		// queue inside `performAndWait` — it never actually crosses to another thread.
		nonisolated(unsafe) let predicate = predicate
		return try self.performAndWait {
			let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
			fetch.predicate = predicate
			fetch.fetchLimit = 1

			return try self.fetch(fetch).first as? NSManagedObject
		}
	}

	/// Fetches all objects of `entityName` matching `predicate` (all objects if `nil`). The fetch
	/// runs on the context's queue and propagates any underlying Core Data error instead of
	/// swallowing it. The returned objects are confined to the context's queue — use them only on
	/// that queue. The `predicate` is a pre-built `NSPredicate`, so callers cannot inject an unbound
	/// format string.
    func fetchList(_ entityName: String, predicate: NSPredicate? = nil) throws -> [NSManagedObject] {
		// `NSPredicate` is not `Sendable`, but it is only read synchronously on the context's own
		// queue inside `performAndWait` — it never actually crosses to another thread.
		nonisolated(unsafe) let predicate = predicate
		return try self.performAndWait {
			let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
			fetch.predicate = predicate

			return try self.fetch(fetch).compactMap { $0 as? NSManagedObject }
		}
	}
}
