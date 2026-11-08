"""Retired wrapper-construction entry point; it did not establish native asset binding."""


def create_prop_bindings(actor_path, course=False):
    mount = '/eda26a53-42c0-4b9e-8f62-31719aef6889'
    if not actor_path.startswith(mount + '/ProCoachLab.'):
        raise RuntimeError('Expected the owned structure device')
    raise RuntimeError(
        'This wrapper-construction route is retired: editor metadata readback reverted '
        'to the default cube after rebuilding. Select an eligible asset through the '
        'native picker, save its owning actor and verify it after a rebuild and at runtime. '
        'Native BuildingWall/BuildingFloor/BuildingStairs/BuildingRoof eligibility is '
        'separate from a BuildingProp control; do not bypass picker or project filters.'
    )
