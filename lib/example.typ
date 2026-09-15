#let style = sys.inputs.at("style", default: none)

#import "./thesis.typ": thesis

#import "../content/ai_usage.typ": ai_usage_list

#thesis(
  config: (
    title: "My title",
    author: "Jane Doe",
    date: none, // TODO: Insert datetime object
    firstsupervisor: "My first supervisor",
    secondsupervisor: "My second supervisor",
    degree_type: "master", // "master" or "bachelor"
    lang: "en", // "en" or "de"
    course_of_study: "Applied Computer Science",
    style: style,
  ),
  chapters: (
    // once you have read it, you can comment out the template
    include "../content/template.typ",
    // include "content/content.typ",
  ),
  abstract: include "../content/abstract.typ",
  declaration: include "../content/declaration.typ",
  bib: bibliography(
    "../content/references.bib",
    style: "ieee",
    title: "Bibliography",
  ),
  // appendix: include "content/appendix.typ",
  acknowledgements: include "../content/acknowledgements.typ",
  ai_usage: ai_usage_list,
  // extra config options for the custom style "minimal"
  config_minimal_style: (
    bib_two_columns: false,
    highlight_refs: true,
    highlight_cites: true,
  ),
)

