// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

#let _translations_de = (
  submitted_text: "im Studiengang",
  institution: "Institut für Informatik",
  /*university: "Bachelor- und Masterarbeiten
    an der Georg-August-Universität Göttingen
    ISSN 1612-6793",*/
  university: "Georg-August-Universität Göttingen",
  firstsupervisor_text: "Erstbetreuer*in",
  secondsupervisor_text: "Zweitbetreuer*in",
  chapter: "Kapitel",
  section: "Unterkapitel",
  subsection: "Abschnitt",
  subsubsection: "Unterabschnitt",
  outline_title: "Inhaltsverzeichnis",
)

#let _translations_en = (
  submitted_text: "submitted in partial fulfillment of the requirements\nfor the course",
  institution: "Institute of Computer Science",
  /*university: "Bachelor's and Master's Theses
    at Georg-August-Universität Göttingen
    ISSN 1612-6793",*/
  university: "Georg-August-Universität Göttingen",
  firstsupervisor_text: "First Supervisor",
  secondsupervisor_text: "Second Supervisor",
  chapter: "Chapter",
  section: "Section",
  subsection: "Subsection",
  subsubsection: "Subsubsection",
  outline_title: "Contents",
)

#let de_bachelor = (
  .._translations_de,
  degree_text: "Bachelorarbeit",
)

#let de_master = (
  .._translations_de,
  degree_text: "Masterarbeit",
)

#let de_report = (
  .._translations_de,
  degree_text: "Seminar Report",
)

#let en_bachelor = (
  .._translations_en,
  degree_text: "Bachelor's Thesis",
)

#let en_master = (
  .._translations_en,
  degree_text: "Master's Thesis",
)

#let en_report = (
  .._translations_de,
  degree_text: "Seminar Report",
)
