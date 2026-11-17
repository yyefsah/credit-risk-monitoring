# Thème et palette (catégorielle validée : écarts CVD adjacents ΔE >= 8 ; contraste < 3:1 sur 3 teintes -> étiquettes directes obligatoires)
suppressPackageStartupMessages(library(ggplot2))
PAL <- c(blue = "#2a78d6", orange = "#eb6834", aqua = "#1baf7a", yellow = "#eda100", magenta = "#e87ba4", green = "#008300")
INK <- "#0b0b0b"; INK2 <- "#52514e"; SURFACE <- "#fcfcfb"; GRID <- "#e6e5e1"
theme_bank <- function(base = 11) {
  theme_minimal(base_size = base) %+replace% theme(
    plot.background = element_rect(fill = SURFACE, colour = NA), panel.background = element_rect(fill = SURFACE, colour = NA),
    panel.grid.major = element_line(colour = GRID, linewidth = 0.3), panel.grid.minor = element_blank(),
    axis.text = element_text(colour = INK2), axis.title = element_text(colour = INK2),
    plot.title = element_text(colour = INK, face = "bold", size = base + 2, hjust = 0), plot.subtitle = element_text(colour = INK2, hjust = 0),
    plot.caption = element_text(colour = INK2, size = base - 3, hjust = 0), legend.position = "top", legend.text = element_text(colour = INK2),
    strip.text = element_text(colour = INK, face = "bold", hjust = 0), plot.title.position = "plot", plot.caption.position = "plot")
}
save_fig <- function(p, name, w = 9, h = 5) ggsave(file.path(DIR_FIG, name), p, width = w, height = h, dpi = 150, bg = SURFACE, device = ragg::agg_png)
