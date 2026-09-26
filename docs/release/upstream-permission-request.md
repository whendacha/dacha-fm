# Draft permission request — not sent

To: near.fm / FastNEAR maintainers  
Subject: Permission for Dacha FM iOS client to use the near.fm catalog

Hello,

I am developing Dacha FM, an independently branded native iOS music player. It reads the documented public near.fm API and streams songs directly from the catalog's existing audio URLs. It displays song metadata and artwork without rehosting the audio. The app adds artist-only playback, favorites, playlists and optional private library sync through Meteor wallet authentication. It is currently in TestFlight, and I would like to submit it to the Apple App Store.

Could you confirm in writing whether Dacha FM may:

- Use the near.fm public API and stream/display its catalog, metadata and artwork in the iOS app.
- Use catalog artwork in App Store screenshots demonstrating the app.
- Distribute the app under the Dacha FM name, with any source attribution you require and without implying official affiliation.

Please identify any conditions, API limits, attribution requirements, restrictions or published terms that apply. If you can authorize only part of the catalog, please identify that scope and how we can select the permitted songs and artwork. Please also clarify whether your authorization covers the uploaded content or whether separate creator permission is needed, and which reporting/contact route you want the client to use.

For accurate Apple privacy and age-rating disclosures, please also confirm whether search query text, IP addresses and media requests are retained in production logs, their purposes and retention periods, and whether any data is used for advertising or cross-service tracking. Please explain how reports are handled and objectionable content is filtered, including the availability or frequency of mature lyrics/artwork in the public catalog.

The repository is a GitHub fork of `fastnear/near-fm`, but the shipped native SwiftUI target and separately hosted mobile identity bridge are newly added code; the upstream Rust/web/contract implementation is not compiled into the IPA. I found no explicit license in the upstream repository. If you intend to license that source for use beyond GitHub forking, please point me to the applicable license as a separate matter.

Project: https://github.com/whendacha/dacha-fm  
Contact: whendacha@gmail.com

Thank you.
