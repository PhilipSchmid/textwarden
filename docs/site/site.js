const demo = document.querySelector(".demo");
const word = document.querySelector("#example-word");
const popover = document.querySelector("#native-suggestion");
const more = demo.querySelector(".more");
const menu = document.querySelector("#more-actions");
const replay = demo.querySelector(".replay");
const hint = document.querySelector("#demo-hint");
const status = document.querySelector("#example-status");
const original = word.textContent;

function showPopover(open) {
  popover.hidden = !open;
  word.setAttribute("aria-expanded", String(open));
  menu.hidden = true;
  more.setAttribute("aria-expanded", "false");
}

function finishExample(message) {
  demo.classList.add("resolved");
  word.disabled = true;
  showPopover(false);
  replay.hidden = false;
  hint.textContent = message;
  status.textContent = message;
  replay.focus({preventScroll: true});
}

function applySuggestion() {
  word.textContent = "recommend";
  finishExample("Correction applied.");
}

function closeSuggestion() {
  showPopover(false);
  word.focus({preventScroll: true});
}

function startExample() {
  demo.classList.remove("resolved");
  word.textContent = original;
  word.disabled = false;
  showPopover(true);
  hint.textContent = "Choose “recommend” to try it";
  replay.hidden = true;
}

startExample();
demo.querySelector(".hotspots").hidden = false;
word.addEventListener("click", () => showPopover(true));
word.addEventListener("mouseenter", () => { if (!word.disabled) showPopover(true); });
demo.querySelector(".dismiss").addEventListener("click", closeSuggestion);
demo.querySelector(".replace").addEventListener("click", applySuggestion);
more.addEventListener("click", () => {
  menu.hidden = !menu.hidden;
  more.setAttribute("aria-expanded", String(!menu.hidden));
  if (!menu.hidden) menu.querySelector("button").focus();
});
menu.addEventListener("click", event => {
  if (event.target.tagName === "BUTTON") finishExample("Suggestion dismissed in this example.");
});
replay.addEventListener("click", () => {
  startExample();
  word.focus({preventScroll: true});
  status.textContent = "Example reset.";
});
demo.addEventListener("keydown", event => {
  if (popover.hidden) return;
  if (event.key === "Escape") {
    if (menu.hidden) closeSuggestion();
    else {
      menu.hidden = true;
      more.setAttribute("aria-expanded", "false");
      more.focus();
    }
  }
  if (event.altKey && event.code === "Digit1") {
    event.preventDefault();
    applySuggestion();
  }
});

const tabList = document.querySelector("#examples");
const panels = Array.from(document.querySelectorAll(".gallery figure"));
const tabs = panels.map((panel, index) => {
  const tab = document.createElement("button");
  tab.type = "button";
  tab.id = "tab-" + panel.id;
  tab.textContent = panel.dataset.tab;
  tab.setAttribute("role", "tab");
  tab.setAttribute("aria-controls", panel.id);
  panel.setAttribute("role", "tabpanel");
  panel.setAttribute("aria-labelledby", tab.id);
  tab.addEventListener("click", () => selectExample(index));
  tabList.append(tab);
  return tab;
});

function selectExample(index) {
  panels.forEach((panel, position) => {
    const active = index === position;
    panel.hidden = !active;
    panel.classList.toggle("active", active);
    tabs[position].tabIndex = active ? 0 : -1;
    tabs[position].setAttribute("aria-selected", String(active));
  });
}

function showLinkedExample() {
  const linked = panels.findIndex(panel => "#" + panel.id === location.hash);
  if (linked !== -1) selectExample(linked);
}
tabList.setAttribute("role", "tablist");
selectExample(0);
showLinkedExample();
window.addEventListener("hashchange", showLinkedExample);

const viewer = document.querySelector(".viewer");
const viewerImage = viewer.querySelector(".viewer-image");
const zoom = viewer.querySelector(".viewer-zoom");
if (typeof viewer.showModal === "function") {
  document.querySelectorAll(".capture").forEach(link => {
    link.addEventListener("click", event => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      const image = viewerImage.querySelector("img");
      image.src = link.href;
      image.alt = link.querySelector("img").alt;
      viewer.querySelector("h3").textContent = Array.from(link.querySelectorAll(".capture-bar span"), label => label.textContent).join(" · ");
      viewerImage.classList.remove("actual-size");
      viewerImage.tabIndex = -1;
      zoom.setAttribute("aria-pressed", "false");
      viewer.showModal();
    });
  });
  zoom.addEventListener("click", () => {
    const enlarged = viewerImage.classList.toggle("actual-size");
    zoom.setAttribute("aria-pressed", String(enlarged));
    viewerImage.tabIndex = enlarged ? 0 : -1;
  });
  viewer.querySelector(".viewer-close").addEventListener("click", () => viewer.close());
  viewer.addEventListener("click", event => {
    if (event.target === viewer) viewer.close();
  });
}

const hero = document.querySelector(".hero");
const ribbon = hero.querySelector(".ink-ribbon");
const trackPointer = matchMedia("(hover: hover) and (pointer: fine) and (prefers-reduced-motion: no-preference)");
hero.addEventListener("pointermove", event => {
  if (!trackPointer.matches) return;
  const bounds = hero.getBoundingClientRect();
  ribbon.style.setProperty("--ribbon-x", ((event.clientX - bounds.left) / bounds.width - .5) * 38 + "px");
  ribbon.style.setProperty("--ribbon-y", ((event.clientY - bounds.top) / bounds.height - .5) * 26 + "px");
});
hero.addEventListener("pointerleave", () => {
  ribbon.style.removeProperty("--ribbon-x");
  ribbon.style.removeProperty("--ribbon-y");
});

tabList.addEventListener("keydown", event => {
  const current = tabs.indexOf(event.target);
  if (current === -1) return;
  const positions = {
    ArrowLeft: (current + tabs.length - 1) % tabs.length,
    ArrowRight: (current + 1) % tabs.length,
    Home: 0,
    End: tabs.length - 1
  };
  if (!Object.hasOwn(positions, event.key)) return;
  event.preventDefault();
  const next = positions[event.key];
  selectExample(next);
  tabs[next].focus();
});

if ("IntersectionObserver" in window && matchMedia("(prefers-reduced-motion: no-preference)").matches) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) entry.target.classList.toggle("outside", !entry.isIntersecting);
  });
  document.documentElement.classList.add("motion");
  document.querySelectorAll(".reveal").forEach(element => observer.observe(element));
}
