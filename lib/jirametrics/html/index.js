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

function makeH1Foldable() {
  // Get all H1 elements
  const h1Elements = document.querySelectorAll('body > h1');
  
  if (h1Elements.length === 0) {
    return; // No H1 elements found
  }
  
  // Process each H1 element
  h1Elements.forEach((h1, index) => {
    // Create a unique ID for this section
    const sectionId = `h1-section-${index}`;
    const toggleId = `h1-toggle-${index}`;
    
    // Create a container div for the H1 and its content
    const container = document.createElement('div');
    container.className = 'h1-foldable-section';
    container.id = sectionId;
    
    // Create a toggle button
    const toggleButton = document.createElement('h1');
    toggleButton.id = toggleId;
    toggleButton.className = 'h1-toggle-btn';
    toggleButton.innerHTML = '▼ ' + h1.textContent;
    
    // Create a content container
    const contentContainer = document.createElement('div');
    contentContainer.className = 'h1-content';
    contentContainer.style.cssText = `
      margin-left: 20px;
    `;
    
    // Move the H1 element into the container and replace it with the toggle button
    h1.parentNode.insertBefore(container, h1);
    container.appendChild(toggleButton);
    container.appendChild(contentContainer);
    
    // Move all elements between this H1 and the next H1 (or end of document) into the content container
    let nextElement = h1.nextElementSibling;
    while (nextElement && nextElement.tagName !== 'H1' && nextElement.id !== 'footer') {
      const temp = nextElement.nextElementSibling;
      contentContainer.appendChild(nextElement);
      nextElement = temp;
    }
    
    // Remove the original H1 element
    h1.remove();
    
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
  });
}

// Auto-initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
  makeH1Foldable();
});

// If we switch between light/dark mode then force a refresh so all charts will redraw correctly
// in the other colour scheme.
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', event => {
  location.reload()
})
