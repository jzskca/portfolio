---
theme: solarized_dark.json
---

# GraphQL

`graphene-django` doesn't enforce permission boundaries in nested queries:

```graphql
query getAppointments {
    getAppointments {
        # This list is filtered to only return *my* appointments
        appointments {
            # Dig into the related practitioner record
            practitioner {
                # This appointments list *should* be filtered to return the same
                # list as above, but it will actually return *all* appointments
                # for the practitioner, allowing me to inspect other clients’
                # appointments!
                appointments {
                    client {
                        ...
                    }
                }
            }
        }
    }
}
```

---

## `SafeDjangoObjectType`

```python3
class SafeDjangoObjectType(DjangoObjectType):
    """
    DjangoObjectType that enforces permissions boundaries between tables.

    One-to-one relationships are resolved by calling ``get_node()`` on the
    related Relay node. This allows permissions to be checked and enforced in
    ``get_node()``. ``get_node()`` returns ``None`` by default.

    "Many" relationships are denied by default. To allow them, override
    ``get_queryset()`` and ``return queryset`` to return the related items,
    adding in any permissions checks and filtering as needed.
    """

    @classmethod
    def get_node(cls, _info, _id):
        """Return nothing by default."""
        return None

    @classmethod
    def get_queryset(cls, _queryset, _info):
        """Return an empty result set by default."""
        return cls._meta.model.objects.none()
```

---

## `SafeDjangoObjectType`

```python3
class SafeDjangoObjectType(DjangoObjectType):
    @classmethod
    def __init_subclass_with_meta__(cls, *args, **kwargs):
        for field in cls._meta.fields:
            # Mediate access to related objects via their get_node() methods.
            def _resolver(root, info, model=related_model):
                field_name = snakecase(info.field_name)
                if getattr(root, field_name, None) is None:
                    return None

                try:
                    return registry.get_type_for_model(model).get_node(
                        info, getattr(root, field_name).pk
                    )
                except ObjectDoesNotExist:
                    return None

            setattr(cls, f"resolve_{field}", _resolver)
```

---

## Usage

```python3
class AppointmentNode(SafeDjangoObjectType):

    class Meta:
        model = Appointment

    @classmethod
    def get_node(cls, info, id):
        "Allow access iff the user is linked to the appointment."
        appointment = Appointment.objects.get(pk=id)

        if (
            is_client(info, appointment.client.pk)
            or is_practitioner(info, appointment.practitioner.pk)
        ):
            return appointment

        raise GraphQLUnauthorized()

    @classmethod
    def get_queryset(cls, queryset, info):
        "Limit to the current user's records."

        if is_client(info):
            return queryset.filter(client=info.context.user.client)
        if is_practitioner(info):
            return queryset.filter(practitioner=info.context.user.practitioner)

        raise GraphQLUnauthorized()
```
