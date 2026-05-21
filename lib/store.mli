(** Initialize silt with the given paths. Creates .silt/ and config. *)
val init : string list -> Config.t

(** Install the skill file to .claude/skills/silt/SKILL.md. *)
val install_skill : unit -> [ `Installed | `Already_current | `Skipped_modified ]

(** The embedded skill content. *)
val skill_content : string
