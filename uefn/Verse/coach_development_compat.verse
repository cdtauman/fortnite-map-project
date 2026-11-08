using { /Fortnite.com/AI }

# Existing investigation-only character definitions retain their type references.
# Their executable fixtures are archived outside the island's runtime source.
coach_participant_probe_behavior := class(npc_behavior):
    OnBegin<override>()<suspends>:void = {}

coach_damage_shooter_behavior := class(npc_behavior):
    OnBegin<override>()<suspends>:void = {}
