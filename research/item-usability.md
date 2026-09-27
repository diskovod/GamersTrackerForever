# Equipment usability for saved characters

The client API exposes an item's class/subclass and equip location through
`GetItemInfoInstant`, while `GetItemInfo` supplies the same classification only
when full item information is available. Neither return contract includes a
character-specific equip verdict. See Blizzard's generated
[Item API declaration](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua).

The numeric values used by the module come from Blizzard's generated
[item constants](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua):
weapon class 2, armor class 4; cloth/leather/mail/plate armor subclasses 1–4,
shield 6; and staff 10, dagger 15, wand 19, one-handed mace 4.

Blizzard's [Classic introduction](https://worldofwarcraft.blizzard.com/en-us/news/23317716/taking-your-first-steps-in-world-of-warcraft-classic)
lists each class's permitted armor families. Its [Priest class
page](https://worldofwarcraft.blizzard.com/en-gb/game/classes/priest) lists
daggers, one-handed maces, staves, and wands. A Blizzard [patch note](https://worldofwarcraft.blizzard.com/en-us/news/20110466/legion-beta-patch-notes)
confirms that, before the Legion change, mail/plate unlocks for the relevant
classes occurred at level 40. This addon intentionally ignores temporary
level restrictions when flagging a permanently disallowed armor family.

Decision: only a confirmed class-versus-armor incompatibility or a confirmed
Priest weapon/shield incompatibility yields a red cross. Missing cache/API,
unknown class, custom weapon type, and item-specific class/race/skill/level
rules remain *unknown*, not incompatible. The in-game item tooltip remains
authoritative. The WoW Forever beta may customize equipment rules, so the
module requires live-client verification before claiming those rules are exact.
