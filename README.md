# Personal Notetaking Universal Apple App

This is a universal apple application for my outline-based note-taking flow

## Feature set (running)

- node-based note-taking that doesn't feel like you are typing out a bullet list
  - node-based because it can accommodate very small, random thoughts
- semantic + keyword search on any snippet of text
- a way to dump ideas in, and process later (e.g. Today notes/Inbox)
  - between today notes and inbox, today notes is better for me, because i associate random thoughts with the day i thought of it + i can keep my journal there as well
- template, or auto-fill a node based on a template
  - e.g. for each day's journal, have a few questions as template, so that I don't have to find the questions and paste them in again every day
  - the template is determined by a higher level of categorization (e.g. tags)
- mention any snippet of text inline + view where each snippet of text is mentioned + linked editing
- markdown editor + image + url
- pull highlights and full text from readwise
- ai chat with all my notes
- quick time-to-first-keystroke and load time
- offline edit
- offline search
- sync across devices
- metadata & metadata templates
  - e.g. for every node, it should have created time; for notes, it should have status (e.g. seeding, growing, blossomed, etc.)
  - the metadata fields should also be a template, based on a higher level of categorization (e.g. tags)
- tags
  - i am not sure about tags; because my belief is that, if search is so great, there is no need for tagging or any form of categorization
  - but tags might be a good categorization tool for applying different templates or presets
- the editor should feel good for both writing small thoughts, and a large body of text
  - small thoughts: 1 sentence, maybe with some bullet points
  - large body of text: podcast scripts
  - i don't need to think about how to format either, it just looks good for both

## Feature brainstorm

### 1. Outline-based note-taking

This note-taking app should be an outliner-based note taking. Here are the requirements for this outliner-based note taking system

- Each entry is a block, represented as a bullet point
- Blocks can be infinitely nested through identation.
- Each block is individually addressable and can be linked/referenced elsewhere
- Each block can attach metadata on it (e.g. created at, tags, etc.)

As for the interface for this outline-based note-taking approach, here are the requirements

- Each block itself can be selected as the main view, with all its descendent blocks shown in the view
- the child of the main block view would not be shown as a bullet, so to maintain a regular note look and feel; all the other descendent blocks from the child (e.g. grandchildren, great-grandchildren, etc.) will be shown as bullets and sub-bullets, with appropropriate identation
- Clicking on any block make that block the main view, and display its descendents accordingly

### Markdown editor + image + URL

### 3. Semantic + keyword search

Sometimes I know exactly the words in the block to search for it.
Sometimes I know the synonyms or similar words in the block to seach for it
Sometimes I only know the meaning around that block to search for the block

An intelligent search should be able to surface blocks for the three situations above and rank them intelligent that matches the most to the search query.

An intelligent search should be able to understand semantics so it can "search by meaning", but also have flexibilty for hard filters, like exact word matching.

An intelligent search does not need me to switch between semantic and keyword search. It should intelligently rerank blocks that is semantically similar and/or keyword matched so that the ranking reflects how closely the blocks answer/match with my search query.

This search should work offline as well.

This also serves as the backbone for AI chat, which requires some grounding from the blocks I wrote.

### Today notes / Inbox

### Templates & auto-fill

### Bidirectional linking and editing

When you mentioned a block, the original block displays the mentioned block as a link to the mentioned block. The mentioned block gains a "linked reference" to the block that mentioned it.

I am also able to edit the mentioned text, and reflect the changes to the mentioned block

### Readwise integration

### AI chat with notes

### Quick load time & time-to-first-keystroke

### Offline edit

### Offline search

### Metadata & metadata templates

### Tags

### Flexible editor for small thoughts and large text
