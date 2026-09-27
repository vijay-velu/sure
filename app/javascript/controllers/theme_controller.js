import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { userPreference: String };

  connect() {
    this.startSystemThemeListener();
  }

  disconnect() {
    this.stopSystemThemeListener();
  }

  // Called automatically by Stimulus when the userPreferenceValue changes (e.g., after form submit/page reload)
  userPreferenceValueChanged() {
    this.applyTheme();
  }

  // Called when a theme radio button is clicked
  updateTheme(event) {
    this.applyPreference(event.currentTarget.value);
  }

  // Applies theme based on the userPreferenceValue (from server)
  applyTheme() {
    this.applyPreference(this.userPreferenceValue);
  }

  applyPreference(preference) {
    if (preference === "system") {
      this.setTheme(this.systemPrefersDark());
    } else if (preference === "oled") {
      this.setTheme(true, { oled: true });
    } else {
      this.setTheme(preference === "dark");
    }
  }

  // Sets the data-theme attribute and broadcasts a `theme:change` event so
  // imperative consumers (D3/SVG/canvas) can repaint without polling.
  // OLED keeps data-theme="dark" (so all theme-dark styles and chart repaints apply)
  // and adds data-oled, which only swaps surface/container tokens to true black.
  setTheme(isDark, { oled = false } = {}) {
    const theme = isDark ? "dark" : "light";
    localStorage.theme = oled ? "oled" : theme;
    document.documentElement.setAttribute("data-theme", theme);
    document.documentElement.toggleAttribute("data-oled", oled);
    document.documentElement.dispatchEvent(
      new CustomEvent("theme:change", { detail: { theme } }),
    );
  }

  systemPrefersDark() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  handleSystemThemeChange = (event) => {
    // Only apply system theme changes if the user preference is currently 'system'
    if (this.userPreferenceValue === "system") {
      this.setTheme(event.matches);
    }
  };

  toggle() {
    const currentTheme = document.documentElement.getAttribute("data-theme");
    if (currentTheme === "dark") {
      this.setTheme(false);
    } else {
      this.setTheme(true);
    }
  }

  startSystemThemeListener() {
    this.darkMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    this.darkMediaQuery.addEventListener(
      "change",
      this.handleSystemThemeChange,
    );
  }

  stopSystemThemeListener() {
    if (this.darkMediaQuery) {
      this.darkMediaQuery.removeEventListener(
        "change",
        this.handleSystemThemeChange,
      );
    }
  }
}
