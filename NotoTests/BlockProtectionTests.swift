//
//  BlockProtectionTests.swift
//  NotoTests
//
//  Unit tests for block protection properties (isDeletable, isContentEditableByUser,
//  isReorderable, isMovable).
//

import Testing
import Foundation
import SwiftData
@testable import Noto

struct BlockProtectionTests {

    @Test @MainActor
    func testAllPropertiesDefaultTrue() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(content: "Regular block", sortOrder: 1.0)
        context.insert(block)
        try context.save()

        #expect(block.isDeletable == true)
        #expect(block.isContentEditableByUser == true)
        #expect(block.isReorderable == true)
        #expect(block.isMovable == true)
    }

    @Test @MainActor
    func testProtectedBlockCreation() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(
            content: "Protected",
            sortOrder: 1.0,
            isDeletable: false,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(block)
        try context.save()

        #expect(block.isDeletable == false)
        #expect(block.isContentEditableByUser == false)
        #expect(block.isReorderable == false)
        #expect(block.isMovable == false)
    }

    @Test @MainActor
    func testChildrenOfProtectedBlockHaveDefaults() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let parent = Block(
            content: "Protected Parent",
            sortOrder: 1.0,
            isDeletable: false,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(parent)

        let child = Block(content: "Free Child", parent: parent, sortOrder: 1.0)
        context.insert(child)
        try context.save()

        // Child should have all defaults (true)
        #expect(child.isDeletable == true)
        #expect(child.isContentEditableByUser == true)
        #expect(child.isReorderable == true)
        #expect(child.isMovable == true)
    }

    @Test @MainActor
    func testPartialProtection() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Only non-deletable, but content editable
        let block = Block(
            content: "Partial",
            sortOrder: 1.0,
            isDeletable: false,
            isContentEditableByUser: true,
            isReorderable: true,
            isMovable: false
        )
        context.insert(block)
        try context.save()

        #expect(block.isDeletable == false)
        #expect(block.isContentEditableByUser == true)
        #expect(block.isReorderable == true)
        #expect(block.isMovable == false)
    }

    @Test @MainActor
    func testProtectionPropertiesPersist() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        let block = Block(
            content: "Persist",
            sortOrder: 1.0,
            isDeletable: false,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(block)
        try context.save()

        // Fetch back
        let descriptor = FetchDescriptor<Block>()
        let blocks = try context.fetch(descriptor)
        let fetched = blocks.first!

        #expect(fetched.isDeletable == false)
        #expect(fetched.isContentEditableByUser == false)
        #expect(fetched.isReorderable == false)
        #expect(fetched.isMovable == false)
    }
}
