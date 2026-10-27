# Working rules

- Read the actual source before changing it; do not reconstruct it from chat memory.
- Base new talent work on Method.gg's latest verified Mythic+ recommendations.
- Follow the approved gear template in tools/class_data/gear.json and TheOneToRuleThemAll/EXTENDING.txt; change it only at the owner's request.
- Reuse existing code. Prefer small, direct functions and clear names over new layers.
- Keep code easy to read and maintain; do not compress it just to remove lines.
- Keep player text, replies and documentation under 30 lines where practical. Exceed that only for necessary instructions or explanation.
- Use plain language. Include only what the reader needs to act or understand.
- Test concrete failure risks, especially placement and recovery. Avoid tests that merely repeat the implementation.
- Passing mocks does not prove correct behavior in WoW. Keep actual client checks separate.
- Keep personal builds and research out of public commits and packages; preserve private originals separately.
- Develop on astra and apply owner-approved changes to main without waiting for Claude.
- Use combined later for reviewed Astra and Claude contributions; keep the branches separate.
- New gameplay changes still need the owner's acceptance in WoW before promotion to main.
- Finish all classes, Method Mythic+ variants and racial handling before handing the complete build over for WoW testing.
