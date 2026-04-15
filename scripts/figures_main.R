# =====================================================================
# Figure regeneration - Figures 2 and 3 from the manuscript
#
# Prerequisites:
#   1. scripts/primary_analysis.R has been run and produced primary_results.rds
#   2. Delirium subgroup and assessment-threshold results are available
#      (these come from the full analytic pipeline; see Supplementary Methods)
#
# This script reproduces:
#   Figure 2: Primary mortality + VFD-28 + ICU LOS forest plot
#   Figure 3: Delirium hazard by assessment adequacy + HR by ventilation status
# =====================================================================

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(patchwork); library(scales)
})

STUDY_ROOT <- Sys.getenv("STUDY_ROOT", unset = ".")
FIG_DIR <- file.path(STUDY_ROOT, "figures")
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- Color scheme ----
col_mimic <- "#1f78b4"
col_eicu  <- "#e6550d"
col_pool  <- "grey20"

thm <- theme_bw(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        strip.background = element_rect(fill = "grey95", color = NA),
        strip.text = element_text(face = "bold"),
        plot.title = element_text(face = "bold", size = 12),
        plot.caption = element_text(hjust = 0, size = 8, color = "grey30"),
        legend.position = "none")

# =====================================================================
# Figure 2 - Primary mortality + unbiased secondary outcomes
# =====================================================================
fig2_df <- tibble::tribble(
  ~outcome, ~group, ~label, ~est, ~lo, ~hi, ~xtype, ~order,
  "30-day mortality (HR)", "MIMIC-IV", "MIMIC-IV\nn=30,924 | 2,971 events", 0.331, 0.278, 0.396, "log", 1,
  "30-day mortality (HR)", "eICU-CRD", "eICU-CRD\nn=34,623 | 4,047 events", 0.506, 0.428, 0.597, "log", 2,
  "30-day mortality (HR)", "Pooled (RE)", "Random-effects pooled\nI^2=91% (tau^2=0.08)", 0.410, 0.271, 0.620, "log", 3,
  "VFD-28 (days, A - B)", "MIMIC-IV", "MIMIC-IV", 2.69, 2.44, 2.95, "lin", 4,
  "VFD-28 (days, A - B)", "eICU-CRD", "eICU-CRD", 1.59, 1.20, 1.93, "lin", 5,
  "ICU length of stay (days, A - B)", "MIMIC-IV", "MIMIC-IV", -1.17, -1.35, -0.98, "lin", 6,
  "ICU length of stay (days, A - B)", "eICU-CRD", "eICU-CRD", -0.44, -0.61, -0.25, "lin", 7
) |> mutate(
  outcome = factor(outcome, levels = unique(outcome)),
  label_unique = paste0(sprintf("%02d_", order), label),
  label_f = factor(label_unique, levels = rev(label_unique)),
  group_col = case_when(grepl("MIMIC", group) ~ col_mimic,
                        grepl("eICU",  group) ~ col_eicu,
                        TRUE ~ col_pool)
)

make_panel <- function(df, xbreaks, xlab, is_log = FALSE, xlim = NULL) {
  df$label_plot <- sub("^\\d+_", "", as.character(df$label_f))
  df$label_plot <- factor(df$label_plot, levels = rev(df$label_plot))
  g <- ggplot(df, aes(x = est, y = label_plot, color = group_col)) +
    geom_vline(xintercept = if (is_log) 1 else 0,
               linetype = "dashed", color = "grey40") +
    geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0, linewidth = 1.2) +
    geom_point(size = 3.5, shape = 18) +
    geom_text(aes(x = hi, label = sprintf(
      if (is_log) "  %.2f (%.2f, %.2f)" else "  %+.2f (%+.2f, %+.2f)",
      est, lo, hi)),
      hjust = 0, color = "black", size = 3.3) +
    scale_color_identity() + labs(x = xlab, y = NULL) + thm
  if (is_log) {
    g <- g + scale_x_log10(breaks = xbreaks, limits = xlim,
                           labels = label_number(accuracy = 0.01))
  } else {
    g <- g + scale_x_continuous(breaks = xbreaks, limits = xlim)
  }
  g
}

p2a <- make_panel(fig2_df |> filter(outcome == "30-day mortality (HR)"),
                  xbreaks = c(0.2, 0.4, 0.6, 0.8, 1, 1.5),
                  xlab = "Hazard ratio (95% CI)",
                  is_log = TRUE, xlim = c(0.2, 2.5)) +
  labs(title = "A. 30-day in-hospital mortality")

p2b <- make_panel(fig2_df |> filter(outcome == "VFD-28 (days, A - B)"),
                  xbreaks = seq(-1, 4, 1),
                  xlab = "Mean difference (A - B), days",
                  xlim = c(-1, 5)) +
  labs(title = "B. Ventilator-free days at 28")

p2c <- make_panel(fig2_df |> filter(outcome == "ICU length of stay (days, A - B)"),
                  xbreaks = seq(-2, 1, 0.5),
                  xlab = "Mean difference (A - B), days",
                  xlim = c(-2, 1)) +
  labs(title = "C. ICU length of stay")

fig2 <- p2a / p2b / p2c + plot_layout(heights = c(3.2, 2.2, 2.2))
ggsave(file.path(FIG_DIR, "Figure2.png"), fig2, width = 9.5, height = 7.5, dpi = 300, bg = "white")

# =====================================================================
# Figure 3 - Ascertainment bias signature
# =====================================================================
# Panel A: delirium HR by assessment threshold (MIMIC-IV, post-hoc)
fig3a_df <- tibble::tribble(
  ~threshold, ~N, ~HR, ~lo, ~hi,
  "All patients (full cohort)", 30924, 1.095, 1.076, 1.114,
  ">=3 total assessments", 21032, 1.060, 1.041, 1.080,
  ">=7 total assessments", 10789, 1.060, 1.034, 1.086,
  ">=10 total assessments", 7260, 1.039, 1.008, 1.071,
  ">=1 per ICU-day",       22667, 1.062, 1.043, 1.081,
  ">=2 per ICU-day",       14599, 1.060, 1.038, 1.083
) |> mutate(
  label = sprintf("%s\nn=%s", threshold, format(N, big.mark = ",")),
  label = factor(label, levels = rev(label))
)

# Panel B: mortality + delirium by ventilation status (MIMIC + eICU)
fig3b_df <- tibble::tribble(
  ~outcome, ~db, ~stratum, ~est, ~lo, ~hi,
  "Mortality HR",  "MIMIC-IV", "Ventilated (n=18,525)",     0.266, 0.213, 0.331,
  "Mortality HR",  "MIMIC-IV", "Non-ventilated (n=12,399)", 0.517, 0.385, 0.693,
  "Mortality HR",  "eICU-CRD", "Ventilated (n=14,101)",     0.451, 0.365, 0.559,
  "Mortality HR",  "eICU-CRD", "Non-ventilated (n=20,522)", 0.637, 0.487, 0.833,
  "Delirium HR",   "MIMIC-IV", "Ventilated",                1.082, 1.060, 1.104,
  "Delirium HR",   "MIMIC-IV", "Non-ventilated",            1.143, 1.108, 1.180,
  "Delirium HR",   "eICU-CRD", "Ventilated",                1.092, 1.025, 1.162,
  "Delirium HR",   "eICU-CRD", "Non-ventilated",            1.064, 1.015, 1.114
) |> mutate(
  outcome = factor(outcome, levels = c("Mortality HR", "Delirium HR")),
  stratum = factor(stratum, levels = rev(unique(stratum))),
  color = ifelse(db == "MIMIC-IV", col_mimic, col_eicu)
)

p3a <- ggplot(fig3a_df, aes(x = HR, y = label)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey40") +
  geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0,
                 linewidth = 1.2, color = col_mimic) +
  geom_point(size = 3.5, shape = 18, color = col_mimic) +
  geom_text(aes(x = hi, label = sprintf("  %.2f (%.2f, %.2f)", HR, lo, hi)),
            hjust = 0, size = 3.3, color = "black") +
  scale_x_log10(breaks = c(0.95, 1, 1.05, 1.1, 1.15),
                limits = c(0.95, 1.35),
                labels = label_number(accuracy = 0.01)) +
  labs(title = "A. Delirium HR across assessment-adequacy thresholds (MIMIC-IV, post-hoc)",
       x = "Delirium hazard ratio (multimodal vs opioid-mono)",
       y = NULL) + thm

p3b <- ggplot(fig3b_df, aes(x = est, y = stratum, color = color)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey40") +
  geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0, linewidth = 1.2) +
  geom_point(size = 3.5, shape = 18) +
  geom_text(aes(x = hi, label = sprintf("  %.2f (%.2f, %.2f)", est, lo, hi)),
            hjust = 0, size = 3.1, color = "black") +
  scale_color_identity() +
  scale_x_log10(breaks = c(0.2, 0.4, 0.6, 0.8, 1, 1.2, 1.5),
                limits = c(0.18, 2.0),
                labels = label_number(accuracy = 0.01)) +
  facet_wrap(~ outcome, ncol = 1, scales = "free_y") +
  labs(title = "B. Hazard ratios stratified by ventilation status",
       x = "Hazard ratio (95% CI)", y = NULL) + thm

fig3 <- p3a / p3b + plot_layout(heights = c(1.0, 1.5))
ggsave(file.path(FIG_DIR, "Figure3.png"), fig3, width = 9.5, height = 10, dpi = 300, bg = "white")

cat("Figures 2 and 3 regenerated\n")
