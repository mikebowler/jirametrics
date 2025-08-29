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
// If we switch between light/dark mode then force a refresh so all charts will redraw correctly
// in the other colour scheme.
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', event => {
  location.reload()
})
