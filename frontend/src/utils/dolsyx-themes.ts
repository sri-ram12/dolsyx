export interface ChatTheme {
  id: string;
  name: string;
  primaryColor: string;
  secondaryColor: string;
  backgroundColor: string;
  surfaceColor: string;
  bubbleSender: string;
  bubbleReceiver: string;
  textPrimary: string;
  textSecondary: string;
  inputBarColor: string;
  dividerColor: string;
  isDark: boolean;
}

// 26 Built-In Android Themes from mobile_app/lib/theme/theme_manager.dart
export const DOLSYX_THEMES: ChatTheme[] = [
  // 1. WhatsApp Green (Default)
  {
    id: "default_whatsapp",
    name: "WhatsApp Green",
    primaryColor: "#128C7E",
    secondaryColor: "#25D366",
    backgroundColor: "#ECE5DD",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#E2FFC7",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#000000",
    textSecondary: "#757575",
    inputBarColor: "#FFFFFF",
    dividerColor: "#E0E0E0",
    isDark: false,
  },
  // 2. Midnight Black
  {
    id: "midnight_black",
    name: "Midnight Black",
    primaryColor: "#1F2C34",
    secondaryColor: "#00A884",
    backgroundColor: "#0B141A",
    surfaceColor: "#1F2C34",
    bubbleSender: "#005C4B",
    bubbleReceiver: "#202C33",
    textPrimary: "#E9EDEF",
    textSecondary: "#8696A0",
    inputBarColor: "#202C33",
    dividerColor: "#2A3942",
    isDark: true,
  },
  // 3. Ocean Blue
  {
    id: "ocean_blue",
    name: "Ocean Blue",
    primaryColor: "#0277BD",
    secondaryColor: "#039BE5",
    backgroundColor: "#E1F5FE",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#B3E5FC",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#000000",
    textSecondary: "#0277BD",
    inputBarColor: "#FFFFFF",
    dividerColor: "#B3E5FC",
    isDark: false,
  },
  // 4. Purple Galaxy
  {
    id: "purple_galaxy",
    name: "Purple Galaxy",
    primaryColor: "#4A148C",
    secondaryColor: "#7B1FA2",
    backgroundColor: "#120024",
    surfaceColor: "#2A004F",
    bubbleSender: "#5E35B1",
    bubbleReceiver: "#311B92",
    textPrimary: "#FFFFFF",
    textSecondary: "#B39DDB",
    inputBarColor: "#2A004F",
    dividerColor: "#4527A0",
    isDark: true,
  },
  // 5. Sunset Orange
  {
    id: "sunset_orange",
    name: "Sunset Orange",
    primaryColor: "#E65100",
    secondaryColor: "#FF9800",
    backgroundColor: "#FFF3E0",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#FFCC80",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#3E2723",
    textSecondary: "#8D6E63",
    inputBarColor: "#FFFFFF",
    dividerColor: "#FFE0B2",
    isDark: false,
  },
  // 6. Rose Pink
  {
    id: "rose_pink",
    name: "Rose Pink",
    primaryColor: "#C2185B",
    secondaryColor: "#E91E63",
    backgroundColor: "#FCE4EC",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#F8BBD0",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#880E4F",
    textSecondary: "#C2185B",
    inputBarColor: "#FFFFFF",
    dividerColor: "#F48FB1",
    isDark: false,
  },
  // 7. Cyber Neon
  {
    id: "cyber_neon",
    name: "Cyber Neon",
    primaryColor: "#00E5FF",
    secondaryColor: "#FF007F",
    backgroundColor: "#000000",
    surfaceColor: "#111111",
    bubbleSender: "#00838F",
    bubbleReceiver: "#212121",
    textPrimary: "#FFFFFF",
    textSecondary: "#00E5FF",
    inputBarColor: "#111111",
    dividerColor: "#333333",
    isDark: true,
  },
  // 8. Forest Green
  {
    id: "forest_green",
    name: "Forest Green",
    primaryColor: "#2E7D32",
    secondaryColor: "#4CAF50",
    backgroundColor: "#E8F5E9",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#C8E6C9",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#1B5E20",
    textSecondary: "#388E3C",
    inputBarColor: "#FFFFFF",
    dividerColor: "#A5D6A7",
    isDark: false,
  },
  // 9. Minimal White
  {
    id: "minimal_white",
    name: "Minimal White",
    primaryColor: "#000000",
    secondaryColor: "#333333",
    backgroundColor: "#F5F5F5",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#E0E0E0",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#000000",
    textSecondary: "#757575",
    inputBarColor: "#FFFFFF",
    dividerColor: "#EEEEEE",
    isDark: false,
  },
  // 10. Deep Space
  {
    id: "deep_space",
    name: "Deep Space",
    primaryColor: "#1A237E",
    secondaryColor: "#3949AB",
    backgroundColor: "#000000",
    surfaceColor: "#121212",
    bubbleSender: "#283593",
    bubbleReceiver: "#1C1C1C",
    textPrimary: "#E8EAF6",
    textSecondary: "#7986CB",
    inputBarColor: "#121212",
    dividerColor: "#303F9F",
    isDark: true,
  },
  // 11. Cherry Blossom
  {
    id: "cherry_blossom",
    name: "Cherry Blossom",
    primaryColor: "#F06292",
    secondaryColor: "#F48FB1",
    backgroundColor: "#FCE4EC",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#F8BBD0",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#880E4F",
    textSecondary: "#C2185B",
    inputBarColor: "#FFFFFF",
    dividerColor: "#F48FB1",
    isDark: false,
  },
  // 12. Golden Horizon
  {
    id: "golden_horizon",
    name: "Golden Horizon",
    primaryColor: "#FFB300",
    secondaryColor: "#FFCA28",
    backgroundColor: "#FFF8E1",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#FFE082",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#5D4037",
    textSecondary: "#8D6E63",
    inputBarColor: "#FFFFFF",
    dividerColor: "#FFE082",
    isDark: false,
  },
  // 13. Mint Breeze
  {
    id: "mint_breeze",
    name: "Mint Breeze",
    primaryColor: "#00BFA5",
    secondaryColor: "#1DE9B6",
    backgroundColor: "#E0F2F1",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#B2DFDB",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#004D40",
    textSecondary: "#00796B",
    inputBarColor: "#FFFFFF",
    dividerColor: "#80CBC4",
    isDark: false,
  },
  // 14. Titanium Eclipse
  {
    id: "titanium_eclipse",
    name: "Titanium Eclipse",
    primaryColor: "#38BDF8",
    secondaryColor: "#0EA5E9",
    backgroundColor: "#0F172A",
    surfaceColor: "#1E293B",
    bubbleSender: "#0369A1",
    bubbleReceiver: "#334155",
    textPrimary: "#F8FAFC",
    textSecondary: "#94A3B8",
    inputBarColor: "#1E293B",
    dividerColor: "#0284C7",
    isDark: true,
  },
  // 15. Royal Purple
  {
    id: "royal_purple",
    name: "Royal Purple",
    primaryColor: "#6200EA",
    secondaryColor: "#651FFF",
    backgroundColor: "#EDE7F6",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#D1C4E9",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#311B92",
    textSecondary: "#512DA8",
    inputBarColor: "#FFFFFF",
    dividerColor: "#B39DDB",
    isDark: false,
  },
  // 16. Slate Gray
  {
    id: "slate_gray",
    name: "Slate Gray",
    primaryColor: "#607D8B",
    secondaryColor: "#78909C",
    backgroundColor: "#ECEFF1",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#CFD8DC",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#263238",
    textSecondary: "#455A64",
    inputBarColor: "#FFFFFF",
    dividerColor: "#B0BEC5",
    isDark: false,
  },
  // 17. Emerald Oasis
  {
    id: "emerald_oasis",
    name: "Emerald Oasis",
    primaryColor: "#00695C",
    secondaryColor: "#00897B",
    backgroundColor: "#E0F2F1",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#80CBC4",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#004D40",
    textSecondary: "#00695C",
    inputBarColor: "#FFFFFF",
    dividerColor: "#B2DFDB",
    isDark: false,
  },
  // 18. Nordic Ice
  {
    id: "nordic_ice",
    name: "Nordic Ice",
    primaryColor: "#0288D1",
    secondaryColor: "#03A9F4",
    backgroundColor: "#E1F5FE",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#81D4FA",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#01579B",
    textSecondary: "#0288D1",
    inputBarColor: "#FFFFFF",
    dividerColor: "#B3E5FC",
    isDark: false,
  },
  // 19. Tokyo Cyberpunk
  {
    id: "tokyo_cyberpunk",
    name: "Tokyo Cyberpunk",
    primaryColor: "#FF007F",
    secondaryColor: "#00E5FF",
    backgroundColor: "#0D0221",
    surfaceColor: "#19053A",
    bubbleSender: "#5E0035",
    bubbleReceiver: "#260C4C",
    textPrimary: "#FFFFFF",
    textSecondary: "#FF007F",
    inputBarColor: "#19053A",
    dividerColor: "#4A0033",
    isDark: true,
  },
  // 20. Coffee Espresso
  {
    id: "coffee_espresso",
    name: "Coffee Espresso",
    primaryColor: "#4E342E",
    secondaryColor: "#6D4C41",
    backgroundColor: "#EFEBE9",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#D7CCC8",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#3E2723",
    textSecondary: "#5D4037",
    inputBarColor: "#FFFFFF",
    dividerColor: "#BCAAA4",
    isDark: false,
  },
  // 21. Nordic Aurora
  {
    id: "nordic_aurora",
    name: "Nordic Aurora",
    primaryColor: "#10B981",
    secondaryColor: "#06B6D4",
    backgroundColor: "#0A192F",
    surfaceColor: "#112240",
    bubbleSender: "#065F46",
    bubbleReceiver: "#1E3A5F",
    textPrimary: "#E2E8F0",
    textSecondary: "#64FFDA",
    inputBarColor: "#112240",
    dividerColor: "#0D9488",
    isDark: true,
  },
  // 22. Lavender Dreams
  {
    id: "lavender_dreams",
    name: "Lavender Dreams",
    primaryColor: "#7E57C2",
    secondaryColor: "#9575CD",
    backgroundColor: "#F3E5F5",
    surfaceColor: "#FFFFFF",
    bubbleSender: "#D1C4E9",
    bubbleReceiver: "#FFFFFF",
    textPrimary: "#4A148C",
    textSecondary: "#6A1B9A",
    inputBarColor: "#FFFFFF",
    dividerColor: "#E1BEE7",
    isDark: false,
  },
  // 23. Cyberpunk Neon
  {
    id: "cyberpunk_neon",
    name: "Cyberpunk Neon",
    primaryColor: "#EC4899",
    secondaryColor: "#A855F7",
    backgroundColor: "#0B0C16",
    surfaceColor: "#18152E",
    bubbleSender: "#701A75",
    bubbleReceiver: "#2E1065",
    textPrimary: "#FDF4FF",
    textSecondary: "#F472B6",
    inputBarColor: "#18152E",
    dividerColor: "#A855F7",
    isDark: true,
  },
  // 24. Amethyst Glow
  {
    id: "amethyst_glow",
    name: "Amethyst Glow",
    primaryColor: "#8E24AA",
    secondaryColor: "#AB47BC",
    backgroundColor: "#14031B",
    surfaceColor: "#260633",
    bubbleSender: "#6A1B9A",
    bubbleReceiver: "#380949",
    textPrimary: "#F3E5F5",
    textSecondary: "#CE93D8",
    inputBarColor: "#260633",
    dividerColor: "#4A148C",
    isDark: true,
  },
  // 25. Velvet Midnight
  {
    id: "velvet_midnight",
    name: "Velvet Midnight",
    primaryColor: "#8B5CF6",
    secondaryColor: "#C084FC",
    backgroundColor: "#130E26",
    surfaceColor: "#221742",
    bubbleSender: "#581C87",
    bubbleReceiver: "#3B1E6D",
    textPrimary: "#FAF5FF",
    textSecondary: "#D8B4FE",
    inputBarColor: "#221742",
    dividerColor: "#7C3AED",
    isDark: true,
  },
  // 26. Titanium Stealth
  {
    id: "titanium_stealth",
    name: "Titanium Stealth",
    primaryColor: "#37474F",
    secondaryColor: "#455A64",
    backgroundColor: "#101417",
    surfaceColor: "#1C2328",
    bubbleSender: "#263238",
    bubbleReceiver: "#1E272C",
    textPrimary: "#ECEFF1",
    textSecondary: "#90A4AE",
    inputBarColor: "#1C2328",
    dividerColor: "#37474F",
    isDark: true,
  },
];

// Map of 20 Solid Colors identical to Android WallpaperSelectionScreen
export const WALLPAPER_SOLID_COLORS = [
  "#000000", "#FFFFFF", "#004D40", "#01579B", "#4DD0E1",
  "#4A148C", "#9C27B0", "#1A237E", "#E65100", "#FF7043",
  "#E91E63", "#FFAB91", "#00BFA5", "#827717", "#4E342E",
  "#006064", "#00BCD4", "#3F51B5", "#212121", "#424242",
];

// Map of 30 Gradient Patterns identical to Android WallpaperSelectionScreen
export const WALLPAPER_GRADIENT_PATTERNS = [
  { id: "sunset", label: "Sunset", colors: ["#ff7e5f", "#feb47b"] },
  { id: "ocean", label: "Ocean", colors: ["#00c6ff", "#0072ff"] },
  { id: "mint", label: "Mint", colors: ["#f79d00", "#64f38c"] },
  { id: "pink", label: "Pink", colors: ["#f953c6", "#b91d73"] },
  { id: "green", label: "Green", colors: ["#11998e", "#38ef7d"] },
  { id: "purple", label: "Purple", colors: ["#8e2de2", "#4a00e0"] },
  { id: "sky", label: "Sky", colors: ["#4ca1af", "#c4e0e5"] },
  { id: "contrast", label: "Contrast", colors: ["#108dc7", "#ef8e38"] },
  { id: "fire", label: "Fire", colors: ["#fc4a1a", "#f7b733"] },
  { id: "deep", label: "Deep", colors: ["#2b5876", "#4e4376"] },
  { id: "neon_violet", label: "Neon Violet", colors: ["#7f00ff", "#e100ff"] },
  { id: "cyber_cyan", label: "Cyber Cyan", colors: ["#00f2fe", "#4facfe"] },
  { id: "peach_sorbet", label: "Peach Sorbet", colors: ["#fa709a", "#fee140"] },
  { id: "teal_midnight", label: "Teal Midnight", colors: ["#30cfd0", "#330867"] },
  { id: "aurora_mint", label: "Aurora Mint", colors: ["#a8ff78", "#78ffd6"] },
  { id: "flamingo_red", label: "Flamingo Red", colors: ["#ff0844", "#ffb199"] },
  { id: "nordic_sky", label: "Nordic Sky", colors: ["#0f172a", "#38bdf8"] },
  { id: "electric_indigo", label: "Electric Indigo", colors: ["#b92b27", "#1565c0"] },
  { id: "velvet_dusk", label: "Velvet Dusk", colors: ["#3a1c71", "#d76d77"] },
  { id: "emerald_glow", label: "Emerald Glow", colors: ["#43e97b", "#38f9d7"] },
  { id: "rose_pastel", label: "Rose Pastel", colors: ["#ff9a9e", "#fecfef"] },
  { id: "royal_orbit", label: "Royal Orbit", colors: ["#6a11cb", "#2575fc"] },
  { id: "titanium_slate", label: "Titanium Slate", colors: ["#0f172a", "#1e293b"] },
  { id: "night_shadow", label: "Night Shadow", colors: ["#141e30", "#243b55"] },
  { id: "obsidian_dark", label: "Obsidian Dark", colors: ["#000000", "#434343"] },
  { id: "crimson_pulse", label: "Crimson Pulse", colors: ["#f857a6", "#ff5858"] },
  { id: "lavender_mist", label: "Lavender Mist", colors: ["#e0c3fc", "#8ec5fc"] },
  { id: "ice_cloud", label: "Ice Cloud", colors: ["#c2e9fb", "#a1c4fd"] },
  { id: "gold_rush", label: "Gold Rush", colors: ["#ffd269", "#ff4500"] },
  { id: "cosmic_rose", label: "Cosmic Rose", colors: ["#1d2b64", "#f8cdda"] },
];

export interface WallpaperConfig {
  type: "default" | "solid" | "pattern" | "custom";
  value: string; // Hex color, comma-separated gradient hexes, or image data URL/url
  opacity: number; // 0.05 to 1.0
  blur: number; // 0 to 10px
}

export const DEFAULT_WALLPAPER: WallpaperConfig = {
  type: "default",
  value: "",
  opacity: 1.0,
  blur: 0,
};

export function getThemeById(id: string): ChatTheme {
  const found = DOLSYX_THEMES.find((t) => t.id === id);
  return found || DOLSYX_THEMES[1]; // default to Midnight Black or WhatsApp Green
}

export function applyThemeToDocument(theme: ChatTheme) {
  if (typeof window === "undefined") return;
  const root = document.documentElement;

  root.style.setProperty("--theme-primary", theme.primaryColor);
  root.style.setProperty("--theme-secondary", theme.secondaryColor);
  root.style.setProperty("--theme-accent", theme.primaryColor);
  root.style.setProperty("--theme-accent-hover", theme.secondaryColor);
  root.style.setProperty("--theme-accent-text", theme.isDark ? "#ffffff" : "#000000");

  root.style.setProperty("--theme-bg-app", theme.backgroundColor);
  root.style.setProperty("--theme-bg-container", theme.isDark ? "rgba(255, 255, 255, 0.02)" : "rgba(255, 255, 255, 0.7)");
  root.style.setProperty("--theme-bg-sidebar", theme.surfaceColor);
  root.style.setProperty("--theme-bg-sidebar-header", theme.surfaceColor);
  root.style.setProperty("--theme-bg-sidebar-search", theme.isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.04)");
  root.style.setProperty("--theme-bg-sidebar-item-hover", theme.isDark ? "rgba(255, 255, 255, 0.05)" : "rgba(0, 0, 0, 0.04)");
  root.style.setProperty("--theme-border-color", theme.dividerColor);

  root.style.setProperty("--theme-text-primary", theme.textPrimary);
  root.style.setProperty("--theme-text-secondary", theme.textSecondary);

  root.style.setProperty("--theme-bubble-sent", theme.bubbleSender);
  root.style.setProperty("--theme-bubble-received", theme.bubbleReceiver);
  root.style.setProperty("--theme-bubble-sent-text", theme.textPrimary);
  root.style.setProperty("--theme-bubble-received-text", theme.textPrimary);
  root.style.setProperty("--theme-checkmark-color", theme.secondaryColor);

  root.style.setProperty("--theme-bg-chat", theme.backgroundColor);
  root.style.setProperty("--theme-bg-chat-header", theme.surfaceColor);
  root.style.setProperty("--theme-bg-chat-input", theme.inputBarColor);
  root.style.setProperty("--theme-bg-chat-input-field", theme.isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.04)");

  root.style.colorScheme = theme.isDark ? "dark" : "light";
}
