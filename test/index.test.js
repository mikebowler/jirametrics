/**
 * Test suite for lib/jirametrics/html/index.js
 * Tests the makeFoldable functionality and DOM manipulation
 */

describe('makeFoldable functionality', () => {
  beforeEach(() => {
    // Clean slate for each test
    document.body.innerHTML = '';
  });

  describe('basic foldable functionality', () => {
    test('should create foldable sections from elements with foldable class', () => {
      createTestHTML();
      loadAndExecuteJS();

      const foldableSections = document.querySelectorAll('.foldable-section');
      expect(foldableSections).toHaveLength(2);
    });

    test('should create toggle buttons for each foldable element', () => {
      createTestHTML();
      loadAndExecuteJS();

      const toggleButtons = document.querySelectorAll('.foldable-toggle-btn');
      expect(toggleButtons).toHaveLength(2);
      
      // Check that toggle buttons have correct content
      expect(toggleButtons[0].innerHTML).toContain('▼ Section 1');
      expect(toggleButtons[1].innerHTML).toContain('▼ Section 2');
    });

    test('should create content containers for each foldable section', () => {
      createTestHTML();
      loadAndExecuteJS();

      const contentContainers = document.querySelectorAll('.foldable-content');
      expect(contentContainers).toHaveLength(2);
      
      // Check that content containers have correct styling
      contentContainers.forEach(container => {
        expect(container.style.borderLeft).toBe('2px solid #ccc');
        expect(container.style.paddingLeft).toBe('15px');
      });
    });

    test('should move content between foldable elements into content containers', () => {
      createTestHTML();
      loadAndExecuteJS();

      const contentContainers = document.querySelectorAll('.foldable-content');
      expect(contentContainers[0].textContent.trim()).toBe('Content 1');
      expect(contentContainers[1].textContent.trim()).toBe('Content 2');
    });
  });

  describe('toggle functionality', () => {
    test('should toggle content visibility on button click', () => {
      createTestHTML();
      loadAndExecuteJS();

      const toggleButton = document.querySelector('.foldable-toggle-btn');
      const contentContainer = document.querySelector('.foldable-content');
      
      // Initially visible
      expect(contentContainer.style.display).toBe('block');
      expect(toggleButton.innerHTML).toContain('▼');
      
      // Click to hide
      toggleButton.click();
      expect(contentContainer.style.display).toBe('none');
      expect(toggleButton.innerHTML).toContain('▶');
      
      // Click to show again
      toggleButton.click();
      expect(contentContainer.style.display).toBe('block');
      expect(toggleButton.innerHTML).toContain('▼');
    });

    test('should toggle multiple sections independently', () => {
      createTestHTML();
      loadAndExecuteJS();

      const toggleButtons = document.querySelectorAll('.foldable-toggle-btn');
      const contentContainers = document.querySelectorAll('.foldable-content');
      
      // Toggle first section
      toggleButtons[0].click();
      expect(contentContainers[0].style.display).toBe('none');
      expect(contentContainers[1].style.display).toBe('block');
      
      // Toggle second section
      toggleButtons[1].click();
      expect(contentContainers[0].style.display).toBe('none');
      expect(contentContainers[1].style.display).toBe('none');
    });
  });

  describe('special cases', () => {
    test('should skip footer elements', () => {
      createTestHTML();
      loadAndExecuteJS();

      const footer = document.getElementById('footer');
      expect(footer).toBeTruthy();
      expect(footer.classList.contains('foldable-section')).toBe(false);
      
      // Footer should not be moved into a content container
      const contentContainers = document.querySelectorAll('.foldable-content');
      contentContainers.forEach(container => {
        expect(container.querySelector('#footer')).toBeNull();
      });
    });

    test('should handle startFolded class correctly', () => {
      createTestHTML(`
        <div class="foldable startFolded">Folded Section</div>
        <p>Content for folded section</p>
        <div class="foldable">Normal Section</div>
        <p>Content for normal section</p>
      `);
      loadAndExecuteJS();

      const contentContainers = document.querySelectorAll('.foldable-content');
      const toggleButtons = document.querySelectorAll('.foldable-toggle-btn');
      
      // First section should be folded (hidden)
      expect(contentContainers[0].style.display).toBe('none');
      expect(toggleButtons[0].innerHTML).toContain('▶');
      
      // Second section should be expanded (visible)
      expect(contentContainers[1].style.display).toBe('block');
      expect(toggleButtons[1].innerHTML).toContain('▼');
    });

    test('should handle empty foldable elements', () => {
      createTestHTML(`
        <div class="foldable">Empty Section</div>
        <div class="foldable">Another Section</div>
        <p>Content</p>
      `);
      loadAndExecuteJS();

      const contentContainers = document.querySelectorAll('.foldable-content');
      expect(contentContainers).toHaveLength(2);
      
      // First section should be empty
      expect(contentContainers[0].textContent.trim()).toBe('');
      
      // Second section should contain the content
      expect(contentContainers[1].textContent.trim()).toBe('Content');
    });

    test('should handle no foldable elements gracefully', () => {
      createTestHTML(`
        <p>No foldable elements here</p>
        <div>Just regular content</div>
      `);
      loadAndExecuteJS();

      const foldableSections = document.querySelectorAll('.foldable-section');
      expect(foldableSections).toHaveLength(0);
    });
  });

  describe('DOM event handling', () => {
    test('should auto-initialize on DOMContentLoaded', () => {
      createTestHTML();
      
      // Load the JS but don't execute makeFoldable directly
      const fs = require('fs');
      const path = require('path');
      const jsCode = fs.readFileSync(path.join(__dirname, '../lib/jirametrics/html/index.js'), 'utf8');
      eval(jsCode);
      
      // Simulate DOM ready
      simulateDOMReady();
      
      const foldableSections = document.querySelectorAll('.foldable-section');
      expect(foldableSections).toHaveLength(2);
    });

    test('should handle dark mode change by reloading page', () => {
      createTestHTML();
      loadAndExecuteJS();
      
      // Trigger the dark mode change
      triggerDarkModeChange();
      
      expect(window.location.reload).toHaveBeenCalled();
    });
  });

  describe('element structure and IDs', () => {
    test('should create unique IDs for sections and toggles', () => {
      createTestHTML();
      loadAndExecuteJS();

      const sections = document.querySelectorAll('.foldable-section');
      const toggles = document.querySelectorAll('.foldable-toggle-btn');
      
      expect(sections).toHaveLength(2);
      expect(toggles).toHaveLength(2);
      
      // Check unique IDs
      expect(sections[0].id).toBe('foldable-section-0');
      expect(sections[1].id).toBe('foldable-section-1');
      expect(toggles[0].id).toBe('foldable-toggle-0');
      expect(toggles[1].id).toBe('foldable-toggle-1');
    });

    test('should preserve original element tag name for toggle button', () => {
      createTestHTML(`
        <h2 class="foldable">Header Section</h2>
        <p>Content</p>
        <span class="foldable">Span Section</span>
        <p>More content</p>
      `);
      loadAndExecuteJS();

      const toggleButtons = document.querySelectorAll('.foldable-toggle-btn');
      expect(toggleButtons[0].tagName).toBe('H2');
      expect(toggleButtons[1].tagName).toBe('SPAN');
    });
  });

  describe('complex content scenarios', () => {
    test('should handle nested elements in content', () => {
      createTestHTML(`
        <div class="foldable">Complex Section</div>
        <div>
          <h3>Nested Title</h3>
          <ul>
            <li>Item 1</li>
            <li>Item 2</li>
          </ul>
        </div>
        <div class="foldable">Next Section</div>
        <p>Simple content</p>
      `);
      loadAndExecuteJS();

      const contentContainers = document.querySelectorAll('.foldable-content');
      expect(contentContainers).toHaveLength(2);
      
      // First container should have the complex nested content
      expect(contentContainers[0].querySelector('h3')).toBeTruthy();
      expect(contentContainers[0].querySelectorAll('li')).toHaveLength(2);
      
      // Second container should have simple content
      expect(contentContainers[1].textContent.trim()).toBe('Simple content');
    });

    test('should handle multiple consecutive foldable elements', () => {
      createTestHTML(`
        <div class="foldable">Section 1</div>
        <div class="foldable">Section 2</div>
        <div class="foldable">Section 3</div>
        <p>Final content</p>
      `);
      loadAndExecuteJS();

      const contentContainers = document.querySelectorAll('.foldable-content');
      expect(contentContainers).toHaveLength(3);
      
      // First two sections should be empty (no content between them)
      expect(contentContainers[0].textContent.trim()).toBe('');
      expect(contentContainers[1].textContent.trim()).toBe('');
      
      // Third section should have the final content
      expect(contentContainers[2].textContent.trim()).toBe('Final content');
    });
  });
});
