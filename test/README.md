# JavaScript Testing Setup

This directory contains the JavaScript test setup for the Jira Export tool.

## Overview

The project uses Jest with jsdom to test the single JavaScript file (`lib/jirametrics/html/index.js`) that provides foldable section functionality for the HTML reports.

## Files

- `setup.js` - Jest setup file with DOM mocks and helper functions
- `index.test.js` - Comprehensive test suite for the makeFoldable functionality
- `README.md` - This documentation file

## Running Tests

### Run JavaScript tests only:
```bash
npm test
```

### Run with coverage:
```bash
npm run test:coverage
```

### Run in watch mode:
```bash
npm run test:watch
```

### Run via Rake (includes Ruby tests):
```bash
rake test
```

### Run JavaScript tests via Rake:
```bash
rake test_js
```

## Test Coverage

The test suite covers:

- **Basic functionality**: Creating foldable sections, toggle buttons, and content containers
- **Toggle behavior**: Click interactions to show/hide content
- **Special cases**: Footer handling, startFolded class, empty elements
- **DOM events**: Auto-initialization on DOM ready, dark mode detection
- **Element structure**: Unique IDs, tag name preservation
- **Complex scenarios**: Nested content, consecutive foldable elements

## Dependencies

- `jest` - JavaScript testing framework
- `jsdom` - DOM implementation for Node.js
- `jest-environment-jsdom` - Jest environment for DOM testing

## Configuration

Jest configuration is in `package.json` with:
- jsdom test environment
- Custom setup file for DOM mocks
- Coverage collection from the JavaScript source file
- HTML and LCOV coverage reports
