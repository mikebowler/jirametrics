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
    toggleButton.innerHTML = '▼ ' + element.textContent;
    
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

// Auto-initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
  makeFoldable();
});


// If we switch between light/dark mode then force a refresh so all charts will redraw correctly
// in the other colour scheme.
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', event => {
  location.reload()
})

// Draw a diagonal pattern to highlight sections of a bar chart. Based on code found at:
// https://stackoverflow.com/questions/28569667/fill-chart-js-bar-chart-with-diagonal-stripes-or-other-patterns
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
