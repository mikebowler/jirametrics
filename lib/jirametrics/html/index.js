function expand_collapse(link_id, issues_id)  {
  link_text = document.getElementById(link_id).textContent
  if( link_text == 'Show details') {
    document.getElementById(link_id).textContent = 'Hide details'
    document.getElementById(issues_id).style.display = 'block'
  }
  else {
    document.getElementById(link_id).textContent = 'Show details'
    document.getElementById(issues_id).style.display = 'none'
  }
}

function toggle_visibility(open_link_id, close_link_id, toggleable_id) {
  let open_link = document.getElementById(open_link_id)
  let close_link = document.getElementById(close_link_id)
  let toggleable_element = document.getElementById(toggleable_id)

  if(open_link.style.display == 'none') {
    open_link.style.display = 'block'
    close_link.style.display = 'none'
    toggleable_element.style.display = 'none'
  }
  else {
    open_link.style.display = 'none'
    close_link.style.display = 'block'
    toggleable_element.style.display = 'block'
  }
}

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
