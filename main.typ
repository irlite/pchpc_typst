#import "/lib/thesis.typ": thesis

#import "content/ai_usage.typ": ai_usage_list

#thesis(
  config: (
    title: "Seismic Wave Forward Modelling",
    author: "Maxim Barnstorf & Utkarsh Pathak",
    date: none, // TODO: Insert datetime object
    firstsupervisor: "Patrick Höhn",
    secondsupervisor: "",
    degree_type: "report", // "report", "master" or "bachelor"
    lang: "en", // "en" or "de"
    course_of_study: "Applied Computer Science",
    style: "modern", // "modern", "legacy" or "minimal"
  ),
  chapters: (
    // once you have read it, you can comment out the template
    include "content/template.typ",
    // include "content/content.typ",
  ),
  abstract: include "content/abstract.typ",
  declaration: include "content/declaration.typ",
  bib: bibliography(
    "content/references.bib",
    style: "ieee",
    title: "Bibliography",
  ),
  // appendix: include "content/appendix.typ",
  acknowledgements: include "content/acknowledgements.typ",
  ai_usage: ai_usage_list,
)

