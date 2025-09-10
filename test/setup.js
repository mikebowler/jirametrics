// Test setup file for Jest with jsdom
// This file runs before each test file

// Mock window.matchMedia for dark mode detection
const mockMediaQueryList = {
  matches: false,
  media: '',
  onchange: null,
  addListener: jest.fn(), // deprecated
  removeListener: jest.fn(), // deprecated
  addEventListener: jest.fn(),
  removeEventListener: jest.fn(),
  dispatchEvent: jest.fn(),
};

// Store the actual event listener for dark mode
let darkModeEventListener = null;

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: jest.fn().mockImplementation(query => {
    const mediaQuery = {
      ...mockMediaQueryList,
      media: query,
      addEventListener: jest.fn((event, callback) => {
        if (event === 'change' && query === '(prefers-color-scheme: dark)') {
          darkModeEventListener = callback;
        }
      }),
    };
    return mediaQuery;
  }),
});

// Helper to trigger dark mode change
global.triggerDarkModeChange = () => {
  if (darkModeEventListener) {
    darkModeEventListener();
  }
};

// Mock location.reload for dark mode change test
Object.defineProperty(window, 'location', {
  writable: true,
  value: {
    reload: jest.fn(),
  },
});

// Helper function to create test HTML structure
global.createTestHTML = (html = '') => {
  if (html) {
    document.body.innerHTML = html;
  } else {
    document.body.innerHTML = `
      <div class="foldable">Section 1</div>
      <p>Content 1</p>
      <div class="foldable">Section 2</div>
      <p>Content 2</p>
      <div id="footer">Footer</div>
    `;
  }
};

// Helper function to load and execute the JavaScript code
global.loadAndExecuteJS = () => {
  const fs = require('fs');
  const path = require('path');
  const jsCode = fs.readFileSync(path.join(__dirname, '../lib/jirametrics/html/index.js'), 'utf8');
  eval(jsCode);
  // Call makeFoldable directly since it's available in global scope after eval
  if (typeof makeFoldable === 'function') {
    makeFoldable();
  }
};

// Helper function to simulate DOM ready
global.simulateDOMReady = () => {
  const event = new Event('DOMContentLoaded');
  document.dispatchEvent(event);
};

// Clean up after each test
afterEach(() => {
  document.body.innerHTML = '';
  // Reset mocks
  window.location.reload.mockClear();
  window.matchMedia.mockClear();
});
