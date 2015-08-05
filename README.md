# Venn

Venn is a flexible system for resource and capacity management for pools of
shared resources.

# Getting Started

## Installation

See the INSTALL file.

## Defining your Resource Domain

Venn specializes in managing overlapping pools of resources.

### Containers

Containers are logical groupings of providers and do not provide resources
themselves. It's best thought of as a tree, for example: a rack contains two
clusters and two filers.  The clusters contain host containers which have two
providers: compute and memory. The filers both provide I/O and contain logical
shares (which provide storage).

Containers have the table prefix "C\_".

```
             C_Rack
             /    \
            /      \
   C_Cluster       C_Filer
       |          /       \
       |         /         \
    C_Host    P_Share     P_IO
    /    \
   /      \
 P_CPU   P_Memory
```

### Providers

Providers provide countable or named resources that can be consumed. An example
of a countable resource is memory (RAM) and an example of a named resource is
an IP address or hostname.

### Assignment Group Type

An Assignment Group Type (AGT) is a collection of resources (containers and
providers) for a single object.  It uses a YAML-based definition to represent a
tree of resources similar to the diagram in the Containers section.

### Attributes

Attributes are used to "tag" resources, for example:

* Environments (dev, qa, prod, ...)
* Capability (ssd, 10g, ...)
* Owner (dba, IT, finance, ...)

## Configuration

Root config directory: etc/conf

### Providers and Containers

`etc/conf/providers/$name.yml`

The definition config file should start with the root container.

Containers have the following properties:

* name: name of the container
* display_name: friendly name of the container
* table: database table name
* +roles: roles to apply to the Result class
* +rs_roles: roles to apply to the ResultSet class
* primary_field: primary field/name of the provider
* primary_key: PK for the table, generally the primary_field
* indices: column indices to speed up queries
* columns: database columns (see DBIx::Class::ResultSource)

Containers may have containers underneath them, defined under:

* containers:
  * _container_name_: # literally the relationship name for the container (e.g. filer)

Example:

* containers:
  * filer:

Containers may have providers underneath them, defined under:

* subproviders:
  * _provider_name_: # literally the relationship name for the provider (e.g. memory)

Example:

* subproviders:
  * memory:

Providers ("subproviders" under containers) have the following properties:

* class: class name (e.g. Memory)
* name: class name (e.g. Memory)
* display_name: friendly name of the provider
* category: resource category (e.g. compute, memory, storage, io, etc.)
* unit: unit of measure for the resource (e.g. MHz, cores, MB, GB, IOps)
* overcommit_ratio: default overcommit ratio for this resource
* +roles: roles to apply to the Result class
* container_rel: the container relationship name that contains this resource
* table: database table name
* link_column: field name for the parent container, useful for minimal subprovider
* columns: database columns (see DBIx::Class::ResultSource)

As well as any DBIC supported joins, like: belongs_to, might_have, has_one,
many_to_many. Pass the equivalent parameters in YAML format to these.

### Attributes

`etc/conf/attributes.yml`

* table: database table name (can be generated)
* display_name: friendly name of the attribute
* primary_field: primary field/name of the attribute
* primary_key: PK for the table, generally the primary_field
* +rs_roles: additional DBIC ResultSet roles, used to add functionality to the
  attribute
* indices: column indices to speed up queries
* columns: database columns (see DBIx::Class::ResultSource)

### Assignment Group Types

`etc/conf/agt/$name.yml`

In order to build the relationships dynamically in Venn during placement, you
must define the Assignment Group Types as a tree, starting from one of the
providers.

* me: name of the base provider's relationship name (in the schema)
* description: used for display purposes
* provider_class: full class name for the base provider
* root_container_class: the container root of the tree's full class name
* root_container_alias: name of the top-level container (defined in the
  container itself)
* providers: hash of all providers in the AGT and a list of container
  relationships to "walk" to get from the base provider to this provider
* location: hash of all location parameters allowed in placement and the
  container that has the field
* provider_to_location_join: hash of all providers and the join parameters
  (using relationship names) needed to join from the base provider to the
  container with the location field
* join_clause: the join clause needed for the placement strategy to access all
  of the providers in the AGT
* place_format: sprintf-style format string that's returned after a replacement
* place_args: list of DBIC-style column names to satisfy the place_format
* overcommit: list of overcommits hashes in order of priority, the hash
  containing the overcommit name (e.g. overcommit_provider), and the field or
  subroutine name (e.g. '\&get_provider_overcommit') to call on the provider to
  get its overcommit ratio
* overcommit_join: like the other join clauses, this is the dbic join clause to
  access all of the overcommit values

## Adding Functionality (with Moose Roles)

`etc/conf/roles.yml`

Moose roles can be applied at runtime to certain parts of Venn using the
roles.yml config file.

Starting point:

    ---
    Generated: # generated via the DBIC generator
        Result:
            subprovider: # provider classes (P_*)
                - CommonClassAttributes
                - ProviderTypeAttributes
                - SubProvider
            named_resource: # named provider classes (NR_*)
                - CommonClassAttributes
                - NamedResource
            container: # container classes (C_*)
                - CommonClassAttributes
                - ContainerClassAttributes
                - GeneratorHelpers
            attribute: # attribute classes (A_*)
                - CommonClassAttributes
            join: # join table classes (J_*)
                - CommonClassAttributes
        ResultSet:
            subprovider:
                - Provider
            container:
                - AssignmentGroup
    Schema:
        - DB2Hacks
        - AutoDeploy
    Result:
    ResultSet:
        AssignmentGroup:
            - Venn::SchemaRole::ResultSet::Reporting::Billing
    Auth:
        - Venn::ActionRole::MyCustomAuth

# The Placement Engine

The Placement Engine is made up of several components:
* API
  * Request
    * Contains the assignment group type, requested resources, attributes, and
      flags necessary to perform the placement.
  * Result
    * Contains the metadata about the placement, including the request,
      strategy, state of the placement, placement candidate(s), location, debug
      info, assignment group, and commit group.
* Engine
  * Strategies: placement "algorithm"
  * Helpers: helper functions/attributes that can be reused across different
    strategies

## Capacity

The Capacity functions of the Placement Engine can be used to determine past
and present resource capacity based on Assignment Group Types.

## Placement

### Request

Sending a request to the Placement Engine can, depending on the options, result
in a successful placement and an Assignment Group, or a failure due to the lack
of capacity.

To place a set of resources, send a POST to /api/v1/place/$agt/$strategy where
$agt is a valid Assignment Group Type and $strategy is the name of a placement
strategy, like biggest_outlier or random.

The POST should be JSON containing:
* resources
  * required, hash of provider type to amount required
* attributes
  * optional, hash of attributes to values (can be lists of required values,
    they're ANDed)
* location
  * optional, hash of locations for placement, based on assignment group type
    locations
* friendly
  * optional, "friendly" name of the object being placed
* identifier
  * optional, force a specific UUID for the Assignment Group
* commit
  * optional, bool for committing the resources immediately
* additional
  * optional, hash of any additional/miscellaneous options used by strategies
* instances
  * optional, int of how many instances are needed for the placeement
* force_placement
  * optional, bool for forcing placement, ignoring capacity/attribute
    restraints
* manual_placement
  * optional, hash of provider type to placement location to force placement in
    a specific place

Example of a basic placement request:

    {
        resources: {
            cpu: 2,
            memory: 1024,
            disk: 20,
            io: 10
        },
        attributes: {
            environment: "dev",
            tags: [ "ssd", "10g" ]
        },
        location: {
            datacenter: "dc1"
        },
        friendly: "vm100"
    }

### Response

The response from the Placement Engine contains a lot of information:

* The incoming request

```
    {
        state: "Placed",
        request: { ... },
        commit_group_id: "802B5F8F-D9CB-4FB8-8669-A3850375ACEF",
        placement_location: {
            cpu_provider_id: 937,
            cpu_host_name: "myhost.example.com",
            memory_provider_id: 938,
            memory_host_name: "myhost.example.com",
            disk_provider_id: 7723,
            disk_name: "share123"
            io_provider_id: 384,
            io_filer_name: "filer7"
        },
        placement_message: "Placed on myhost.example.com and NAS share share123",
        placement_candidates: [
            # optionally possible placement candidates
        ],
        placement_named_resources: {
            ip_address: "192.168.1.43"
        },
        definition: {
            # AGT definition used for placement
        }
        assignmentgroup: {
        created: 1436217502,
        friendly: "evmx123",
        identifier: "88086E54-2424-11E5-9FB7-E54D9BA11A62",
        assignmentgroup_id: 9,
        assignmentgroup_type_name: "zlight",
        metadata: {
            # metadata about the placement
            request: { ... },
            placement: {
               # optional metadata from the placement strategy
            }
        }
        assignments: [
            {
                created: 1436217502,
                commit_group_id: "8808B86E-2424-11E5-9FB7-E54D9BA11A62",
                resource_id: undef,
                assignment_id: 33,
                assignmentgroup_id: 9,
                committed: 0,
                provider_id: 937,
                size: 2
            },
            {
                created: 1436217502,
                commit_group_id: "8808B86E-2424-11E5-9FB7-E54D9BA11A62",
                resource_id: undef,
                assignment_id: 34,
                assignmentgroup_id: 9,
                committed: 0,
                provider_id: 938,
                size: 1024
            },
            {
                created: 1436217502,
                commit_group_id: "8808B86E-2424-11E5-9FB7-E54D9BA11A62",
                resource_id: undef,
                assignment_id: 35,
                assignmentgroup_id: 9,
                committed: 0,
                provider_id: 7723,
                size: 20
            },
            {
                created: 1436217502,
                commit_group_id: "8808B86E-2424-11E5-9FB7-E54D9BA11A62",
                resource_id: undef,
                assignment_id: 36,
                assignmentgroup_id: 9,
                committed: 0,
                provider_id: 384,
                size: 10
            }
        ]
       },
       placement_info: {
           # metadata from placement strategy
       },
       error: ~ # optional error message
    }
```

# Development

## Running a Test Server

$ `script/testserver.pl $port`

An example of running with the sqlite environment, with a prefix of /venn and
listening on port 8080:

$ `VENN_ENV=sqlite VENN_PREFIX=/venn ./testserver.pl 8080`

## Running the Test Suite

Running tests:

$ `prove -r t`

Running tests concurrently:

$ `prove -j$numthreads -r t`

Example: $ `prove -j4 -r t`

Running tests with database tracing:

$ `DBIC_TRACE=1 DBIC_TRACE_PROFILE=console prove -r t`

## Environment Variables

### Venn-Specific

* VENN\_ENV
  * Venn environment (used for database, etc.)
  * e.g.: sqlite, dev, qa, prod
* VENN\_CONF\_DIR
  * Venn config directory
* VENN\_DEBUG\_GENERATOR
  * Print more info when generating the schema from the yml files
* VENN\_DEPLOY\_NO\_CONSTRAINTS
  * Deploy the database without constraints
* VENN\_DROP\_TABLES
  * Drop tables when deploying
* VENN\_IN\_MEMORY
  * Run in memory (used in conjunction with sqlite)
* VENN\_LOG\_BASE
  * Logging base directory
* VENN\_OVERRIDE\_USER
  * Treat each request as this user
* VENN\_PREFIX
  * Mostly used for the testserver to force a URI prefix (e.g. /venn)
* VENN\_TABLE\_PREFIX
  * Add a prefix to the database tables to act like a namespace
* VENN\_TEST
  * Indicates Venn is in testing mode, currently just disables database
    validation
* VENN\_TEST\_DB\_AUTODEPLOY
  * Don't autodeploy tables when running tests
* VENN\_TEST\_NO\_AUTO\_RESTART
  * Don't autorestart the testserver when making code changes

### Miscellaneous

* DBIC\_TRACE
  * Set to 1 for debug, 1=/tmp/trace.out to write to /tmp/trace.out

## Swagger API Discovery, Documentation, and Testing

### Accessing in the browser

http://$venn:$port/swagger

### Updating the swagger docs

$ `sbin/generate_swagger_documentation.pl`

This will generate the file: `root/swagger/api-docs.json`

# CLI

The Venn CLI is a perl command line interface that can be used to interact with
the Venn API. It can be installed from a separate project: venn-cli.

# UI

The Venn UI is coming soon and will provide AngularJS services and directives to
easily make a custom website to view/manage capacity.

It will be distributed in a separate project: venn-ui.
