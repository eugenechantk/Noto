#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Noto.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Find main target (Noto) and test target (NotoTests)
main_target = project.targets.find { |t| t.name == 'Noto' }
test_target = project.targets.find { |t| t.name == 'NotoTests' }

abort "Could not find Noto target" unless main_target
abort "Could not find NotoTests target" unless test_target

# Find or create the Search group under Noto
noto_group = project.main_group.groups.find { |g| g.name == 'Noto' || g.path == 'Noto' }
abort "Could not find Noto group" unless noto_group

search_group = noto_group.groups.find { |g| g.name == 'Search' }
unless search_group
  search_group = noto_group.new_group('Search', 'Search')
end

tokenizer_group = search_group.groups.find { |g| g.name == 'Tokenizer' }
unless tokenizer_group
  tokenizer_group = search_group.new_group('Tokenizer', 'Tokenizer')
end

# Files to add to the main target's Search group
main_files = [
  'FTS5Database.swift',
  'DirtyTracker.swift',
  'PlainTextExtractor.swift',
  'SearchTypes.swift',
  'DateFilterParser.swift',
  'HybridRanker.swift',
  'BreadcrumbBuilder.swift',
  'FTS5Engine.swift',
  'FTS5Indexer.swift',
  'IndexReconciler.swift',
  'EmbeddingModel.swift',
  'HNSWIndex.swift',
  'SemanticEngine.swift',
  'EmbeddingIndexer.swift',
]

tokenizer_files = [
  'BertTokenizer.swift',
  'WordPieceTokenizer.swift',
]

# Test files
test_files = [
  'SearchFoundationTests.swift',
  'KeywordSearchTests.swift',
  'SemanticSearchTests.swift',
  'HybridLogicTests.swift',
]

# Helper: check if file is already in the group
def file_in_group?(group, filename)
  group.files.any? { |f| f.name == filename || f.path&.end_with?(filename) }
end

# Helper: check if file is already in build phase
def file_in_build_phase?(target, filename)
  target.source_build_phase.files.any? { |bf| bf.file_ref&.name == filename || bf.file_ref&.path&.end_with?(filename) }
end

added = []

# Add main source files
main_files.each do |filename|
  next if file_in_group?(search_group, filename)
  file_ref = search_group.new_reference(filename)
  main_target.source_build_phase.add_file_reference(file_ref)
  added << "Noto/Search/#{filename} -> Noto target"
end

# Add tokenizer files
tokenizer_files.each do |filename|
  next if file_in_group?(tokenizer_group, filename)
  file_ref = tokenizer_group.new_reference(filename)
  main_target.source_build_phase.add_file_reference(file_ref)
  added << "Noto/Search/Tokenizer/#{filename} -> Noto target"
end

# Find or create NotoTests group
test_group = project.main_group.groups.find { |g| g.name == 'NotoTests' || g.path == 'NotoTests' }
abort "Could not find NotoTests group" unless test_group

# Add test files
test_files.each do |filename|
  next if file_in_group?(test_group, filename)
  file_ref = test_group.new_reference(filename)
  test_target.source_build_phase.add_file_reference(file_ref)
  added << "NotoTests/#{filename} -> NotoTests target"
end

if added.empty?
  puts "All files already in project."
else
  project.save
  puts "Added #{added.count} files:"
  added.each { |f| puts "  + #{f}" }
end
