# Website audit

Audit date: 4 October 2026. Scope: the public website at
https://thornswood.net and its report, gallery and authentication services.
This change does not publish a game release or modify either update feed.

## Discovery and page content

| Requested check | Outcome |
| --- | --- |
| Custom domain | Already uses thornswood.net with HTTPS. Public www pages redirect to the apex domain. |
| Proper page sources | All 16 public routes return meaningful HTML before JavaScript runs. News, roadmap, gallery, downloads and report previously depended on JavaScript for their main content. |
| Custom 404 | Unknown pages return HTTP 404, a branded explanation, recovery links, a favicon and noindex metadata. Missing markdown pages no longer return a successful placeholder. |
| Unique titles and descriptions | Each public route has its own title and description. Client rendering preserves the route title. |
| Canonical tags | Each public route names its absolute HTTPS canonical URL. |
| One clear heading | Public HTML contains exactly one h1 per route. Hidden home content is removed from other routes; repeated content headings become h2. |
| sitemap.xml | Lists the 16 public routes, excluding private services and update feeds. |
| robots.txt | Keeps existing private route exclusions, adds the sitemap and excludes game feeds. Robots directives do not replace authentication. |
| llms.txt | Gives public document links and project context. Support by any particular crawler is not guaranteed. |
| Favicon and tab branding | Existing Thornswood favicon retained, including error pages. No Vite or React default titles. |
| Internal links and breadcrumbs | Header, footer, contextual help and policy links retained; each content page gains a breadcrumb trail. |
| Structured data | Organization, WebSite, WebPage and BreadcrumbList describe the actual project. No invented address, company registration or reviews. |
| Social share images | Existing 1200 by 630 branded image retained with Open Graph and Twitter titles, descriptions and image descriptions. |
| Image descriptions | Gallery descriptions use supplied alt text or a descriptive community caption. Decorative preview images have empty alt text. Recordings render as videos rather than broken images. |
| Placeholder content and unsupported claims | Missing content uses truthful empty states. Unsupported comparisons and progress guarantees were removed from the home page. |

Canonical and sitemap choices follow [Google's canonical guidance](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls)
and [sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap).

## Privacy, accessibility and conversion

| Requested check | Outcome |
| --- | --- |
| Privacy, terms and cookie pages | All three exist and are internally linked. Privacy and cookie text now accurately describes Discord sign-in, OAuth state, fallback login and age declaration storage. Policy version hashes preserve prior text history. |
| Cookie consent, analytics and embeds | No Google Analytics, advertising cookies or third-party frames found in the audited public source. Fonts and rendering code are served locally. Links to Discord and Patreon are links, not embedded trackers. Optional tracking must be reviewed before it is added. |
| Form consent and necessary data | Reports explain purpose, storage and the optional Discord name beside submission. Gallery submission explains publication permission and staff review. Forms warn against unrelated personal or sensitive information. A generic mandatory marketing-consent checkbox was not added. |
| Keyboard access and clear labels | Report submission works with the keyboard. Mobile navigation exposes expanded state, supports Escape and returns focus. Send report, Choose pictures, Send pictures and Load more pictures state their actions. Status text uses polite live regions. |
| Color contrast and motion | Report field borders now use the faint palette color rather than the low-contrast edge color, approximately 4.8:1 against their background. Hero motion has a Pause/Play control and respects reduced motion. This focused verification is not a full accessibility certification. |
| Above-the-fold and mobile calls to action | Existing application and download paths remain prominent. Mobile header now keeps a 44-pixel-high Download link visible. Verified at 390 by 844 without horizontal overflow. |
| Response time | The report form explicitly says staff work in their own time and there is no guaranteed response time. A numerical promise requires an actual staffing commitment. |
| Business details and local laws | Existing free fan project description, credits and Discord contact retained. Public operator identity, business jurisdiction and any required service address remain unconfirmed. No details were invented. |
| Image copyright | Existing credits and submission permission/removal terms were inspected. Complete ownership or licensing evidence for every commissioned graphic and community image is not available in this audit; asset provenance remains an operator follow-up. |

The current source does not introduce optional tracking that would justify an
analytics consent banner. Cookie exemptions and applicable obligations depend
on the service and jurisdiction; see the [ICO cookie guidance](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/cookies-and-similar-technologies/).
An age declaration is not proof of age. If UK age-assurance duties apply to
the site's content and audience, self-declaration alone does not meet the
highly effective assurance requirement described by
[Ofcom](https://www.ofcom.org.uk/online-safety/protecting-children/age-assurance).
Operator location and audience must be established before claiming compliance
with a specific local law. This audit does not certify legal compliance.

## Reliability and performance

| Requested check | Outcome |
| --- | --- |
| Console errors | Local report submission, navigation and public rendering checked in a real browser without console errors or warnings. Production verification follows deployment. |
| Production source maps | Public static requests for source maps return 404, including accidentally copied map files. |
| Huge JavaScript bundles | This site has no React/Vite application bundle or new dependencies. Public home.js is 58,105 bytes, 17,544 with gzip; private hub.js is 96,073 bytes, 27,137 with gzip. Existing Caddy gzip remains enabled. Non-home pages no longer include the home video. |
| Rate limits and API limits | Public reads allow 120 requests per minute per connection identity. Uploads allow 40 per hour, 500 MB per hour and two simultaneous streams per identity. Refusals include Retry-After. Existing report and login protections remain. |
| Error handling, loading, empty and failed states | Public requests and JSON bodies have deadlines. Buttons show activity, failed requests produce recovery text and duplicate in-progress clicks are ignored. Empty galleries and news use truthful messages. |
| API timeouts | Public requests expire after 15 seconds, file uploads after 120 seconds in the browser. Server uploads stop after five minutes and delete partial files. No automatic retry can duplicate a report or upload. |
| Database queries and indexes | The site uses bounded JSON records rather than a relational database. SQL indexes are not applicable. Public news/gallery file reads are cached by file version; authentication and ban records are not cached by this change. |
| Pagination and repeated requests | Website gallery loads 24 entries initially and supports bounded pages, at most 60. Loading more preserves draft fields, selected files and active upload locks. Existing launcher API requests retain the complete gallery for compatibility. |
| Upload compression and sizes | Pictures over 2 MB are reduced to at most 2560 pixels and converted to WebP when smaller. GIF animation is preserved. Browser picture cap is 25 MB; existing server caps remain 100 MB for gallery media and 200 MB for general uploads. Gallery signatures and extensions are checked. Partial and invalid files are removed. |
| Upload concurrency | Exclusive filesystem reservation plus randomized names prevents simultaneous uploads with the same source name from overwriting each other. |
| Uptime monitoring and error logging | Existing site/watch/outside-watch scheduled services and rolled logs retained. VPS watch and nightly backup were observed with successful task results on 3 October. No private configuration or logs are published with this report. |
| Simultaneous users | Tests cover 30 simultaneous public page readers and 125 simultaneous API reads: 120 succeed, five receive the expected 429. Concurrent identical upload names preserve separate byte contents. This is bounded functional testing, not a capacity guarantee. |
| Backup restoration | Encrypted backup and restore suite passed 70 checks. A disposable website was deleted and recovered, with all 12 fixture records, configuration, uploads and separate Main/Dev feeds verified byte for byte. Production records were not overwritten for the test. |

## Remaining operational risks

- Confirm the public operator details, jurisdiction and applicable adult-content
  requirements before treating the existing policies as legally complete.
- Keep copyright permission evidence for published graphics and community media.
- Existing nightly backup policy changes behavior when total uploads exceed
  300 MB: larger individual uploads can be omitted. The observed 3 October
  upload set was about 18.8 MB and below that threshold. Review this policy
  before the gallery grows; fixture restoration does not prove every future
  production recording is backed up.
- Browser and contrast checks cover the changed flows, not every assistive
  technology, device or public/private workflow.

## Verification and maintenance

The focused checks include site discovery, server rendering, headers,
authentication, logging, stalled Discord and request bodies, report abuse
limits, frontend deadlines/compression/pagination, upload signatures and
concurrency, policy version history and encrypted backup restoration.
The required VPS build must pass on the exact PR head before merge. Deploy
the merged source with `Deploy-Docs.ps1 -Site`; do not use Ship for this audit.

The following requests were removed by the operator and are excluded:
local business schema, removing fake reviews, enquiry thank-you page,
case studies, five FAQs, maps/directions, customer reviews and team photographs.
