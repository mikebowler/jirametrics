// Apply saved theme immediately (before Chart.js reads CSS variables) so charts
// initialize with the correct colour scheme.
(function () {
  const saved = localStorage.getItem('jirametrics:theme');
  if (saved) {
    document.documentElement.setAttribute('data-theme', saved);
  }
}());

function makeFoldable() {
  // Get all elements with the "foldable" class
  const foldableElements = document.querySelectorAll('.foldable');
  
  if (foldableElements.length === 0) {
    return; // No foldable elements found
  }
  
  // Process each foldable element
  foldableElements.forEach((element, index) => {
    // Skip if this is the footer element
    if (element.id === 'footer') {
      return;
    }
    
    // Create a unique ID for this section
    const sectionId = `foldable-section-${index}`;
    const toggleId = `foldable-toggle-${index}`;
    
    // Create a container div for the foldable element and its content
    const container = document.createElement('div');
    container.className = 'foldable-section';
    container.id = sectionId;
    
    // Create a toggle button
    const toggleButton = document.createElement(element.tagName); //'button');
    toggleButton.id = toggleId;
    toggleButton.className = 'foldable-toggle-btn';
    toggleButton.innerHTML = '▼ ' + element.innerHTML;
    
    // Create a content container
    const contentContainer = document.createElement('div');
    contentContainer.className = 'foldable-content';
    contentContainer.style.cssText = `
      border-left: 2px solid #ccc;
      padding-left: 15px;
    `;
    
    // Move the foldable element into the container and replace it with the toggle button
    element.parentNode.insertBefore(container, element);
    container.appendChild(toggleButton);
    container.appendChild(contentContainer);
    
    // Move all elements between this foldable element and the next foldable element (or end of document) into the content container
    let nextElement = element.nextElementSibling;
    while (nextElement && !nextElement.classList.contains('foldable')) {
      // Skip the footer element
      if (nextElement.id === 'footer') {
        break;
      }
      
      const temp = nextElement.nextElementSibling;
      contentContainer.appendChild(nextElement);
      nextElement = temp;
    }
    
    // Remove the original foldable element
    element.remove();
    
    // Add click event to toggle visibility
    toggleButton.addEventListener('click', function() {
      const content = this.nextElementSibling;
      if (content.style.display === 'none') {
        content.style.display = 'block';
        this.innerHTML = '▼ ' + this.innerHTML.substring(2);
      } else {
        content.style.display = 'none';
        this.innerHTML = '▶ ' + this.innerHTML.substring(2);
      }
    });
    
    // Initially show the content (you can change this to 'none' if you want sections collapsed by default)
    contentContainer.style.display = 'block';
    if(element.classList.contains('startFolded')) {
      toggleButton.click();
    }
  });
}

function initThemeToggle() {
  const html = document.documentElement;
  const saved = localStorage.getItem('jirametrics:theme');
  if (saved) {
    html.setAttribute('data-theme', saved);
  }

  function updateActiveButton(theme) {
    ['system', 'light', 'dark'].forEach(t => {
      const btn = document.getElementById(`theme-btn-${t}`);
      if (btn) {
        btn.classList.toggle('active', t === theme);
      }
    });
  }

  function setTheme(theme) {
    if (theme === 'system') {
      html.removeAttribute('data-theme');
      localStorage.removeItem('jirametrics:theme');
    } else {
      html.setAttribute('data-theme', theme);
      localStorage.setItem('jirametrics:theme', theme);
    }
    updateActiveButton(theme);
    location.reload();
  }

  updateActiveButton(saved || 'system');

  ['system', 'light', 'dark'].forEach(theme => {
    const btn = document.getElementById(`theme-btn-${theme}`);
    if (btn) {
      btn.addEventListener('click', () => setTheme(theme));
    }
  });
}

// Auto-initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
  makeFoldable();
  initThemeToggle();
});


// If we switch between light/dark mode then force a refresh so all charts will redraw correctly
// in the other colour scheme. Skip reload if a manual theme override is set.
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', event => {
  if (!document.documentElement.hasAttribute('data-theme')) {
    location.reload();
  }
})

// Draw a diagonal pattern to highlight sections of a bar chart. Based on code found at:
// https://stackoverflow.com/questions/28569667/fill-chart-js-bar-chart-with-diagonal-stripes-or-other-patterns
// Apply an alpha to a colour that may only be resolvable in the browser, such as one that came
// from a CSS variable. Ruby cannot do this arithmetic any more now that palette colours are
// variables rather than literals.
function withAlpha(color, alpha) {
  const probe = document.createElement('canvas').getContext('2d')
  probe.fillStyle = color
  const resolved = probe.fillStyle  // normalised by the browser to #rrggbb or rgba(...)
  if (resolved.startsWith('#')) {
    const r = parseInt(resolved.substr(1, 2), 16)
    const g = parseInt(resolved.substr(3, 2), 16)
    const b = parseInt(resolved.substr(5, 2), 16)
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }
  return resolved.replace(/^rgb\(/, 'rgba(').replace(/\)$/, `, ${alpha})`)
}

// A y-axis tick callback for charts whose ceiling is deliberately set above their tallest value, so
// you can see that nothing is clipped. Chart.js labels that ceiling too, which gives you an arbitrary
// number like 169 sitting just above 160, or 62 above 50. Drop that label, unless the ceiling happens
// to land exactly on the regular grid, in which case it is a perfectly good label and worth keeping.
// Pass it straight to ticks.callback.
//   ticks 0 20 .. 160 169 -> 169 dropped, it breaks the spacing
//   ticks 0 20 .. 100 120 -> 120 kept, it continues the spacing
function labelExceptCrowdedCeiling(value, index, ticks) {
  if (index !== ticks.length - 1 || index < 2) return value
  let regularGap = ticks[index - 1].value - ticks[index - 2].value
  return value - ticks[index - 1].value === regularGap ? value : null
}

function createDiagonalPattern(color = 'black') {
  // create a 5x5 px canvas for the pattern's base shape
  let shape = document.createElement('canvas')
  shape.width = 5
  shape.height = 5
  // get the context for drawing
  let c = shape.getContext('2d')
  // draw 1st line of the shape 
  c.strokeStyle = color
  c.beginPath()
  c.moveTo(1, 0)
  c.lineTo(5, 4)
  c.stroke()
  // draw 2nd line of the shape 
  c.beginPath()
  c.moveTo(0, 4)
  c.lineTo(1, 5)
  c.stroke()
  // create the pattern from the shape
  return c.createPattern(shape, 'repeat')
}
