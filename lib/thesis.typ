// Copyright (c) 2026 Lorenz Glißmann
// Creative Commons Zero v1.0 Universal

#import "./default_translations.typ"

#let thesis(
  config: none,
  chapters: none,
  abstract: none,
  declaration: none,
  bib: none,
  appendix: none,
  acknowledgements: none,
  ai_usage: none,
  ..args,
) = {
  // validate and clean up arguments
  assert(
    config.at("lang", default: none) in ("de", "en"),
    message: "Only german (de) and english (en) are supported as document languages (lang).",
  )
  assert(
    config.at("degree_type", default: none) in ("bachelor", "master", "report"),
    message: "Please set degree_type to either bachelor or master.",
  )

  if config.at("translations", default: none) == none {
    let key = config.lang + "_" + config.degree_type
    config.translations = dictionary(default_translations).at(key)
  }

  if config.at("date", default: none) == none {
    config.date = datetime.today()
  }
  assert(type(config.date) == datetime, message: "The date must be a datetime object.")

  if config.at("date_format", default: none) == none {
    if config.lang == "en" {
      // use the english date format
      config.date_format = "[month repr:long] [day], [year]"
    } else {
      // use the german date format
      config.date_format = "[day].[month].[year]"
      // language specific month names are not yet supported in typst, but are planned.
      // config.date_format = "[day]. [month repr:long] [year]"
    }
  }

  // set documents properties
  set document(
    author: config.author,
    title: config.title,
    date: config.date,
    description: abstract,
  )
  // set document language
  set text(lang: config.lang)

  // use the specified style
  let style_path = (
    "legacy": "./styles/ugoe-cs-ds/style_legacy.typ",
    "modern": "./styles/ugoe-cs-ds/style_modern.typ",
    "minimal": "./styles/minimal/style_minimal.typ",
  ).at(config.style)
  import style_path: thesis as ts
  ts(
    config,
    chapters,
    abstract: abstract,
    declaration: declaration,
    bib: bib,
    appendix: appendix,
    acknowledgements: acknowledgements,
    ai_usage: ai_usage,
    ..args,
  )
}
