# Ballerina Enhancement Proposal Process

## Table of Contents

<!-- TOC -->
* [Ballerina Enhancement Proposal Process](#ballerina-enhancement-proposal-process)
  * [Table of Contents](#table-of-contents)
  * [Summary](#summary)
  * [Motivation](#motivation)
  * [Ballerina Enhancement Proposals(BEP)](#ballerina-enhancement-proposalsbep-)
    * [What type of work should go to BEP](#what-type-of-work-should-go-to-bep)
    * [BEP Template](#bep-template)
    * [BEP Metadata](#bep-metadata)
    * [BEP Workflow](#bep-workflow)
    * [Where should BEPs be checked](#where-should-beps-be-checked)
<!-- TOC -->

## Summary

The Ballerina platform consists of the Ballerina language, build tooling, libraries, connectors, and integration tools. Currently, only the language and a few build tooling specifications and proposals are managed centrally in the `ballerina-spec` repository. Library specifications and proposals are managed in their respective module repositories, each following a different process. This proposal aims to consolidate all proposals under one framework and establish a standardized approach for creating proposals across the platform.

By introducing a standardized development process for the Ballerina platform, we aim to achieve the following:

- Create a clear structure for proposing changes to the Ballerina platform.
- Clearly explain why the change is needed.
- Keep all project information in one central location.
- Support the development of useful information for users, including:
    - A complete project development roadmap
    - Reasons for important user-facing changes
- Make sure community members can successfully complete changes across one or more releases.

This process is supported by a work unit called a `Ballerina Enhancement Proposal`, or BEP. A BEP aims to integrate elements of a feature, requirement, and design into a single file, which is developed incrementally through collaboration.

## Motivation

We, the Ballerina developers, follow the standard development process defined within our subteam. For example, in the Ballerina Standard Library team, we maintain library specifications in their respective repositories (e.g., the HTTP specification can be found [here](https://github.com/ballerina-platform/module-ballerina-http/blob/master/docs/spec/spec.md)), and we adhere to the [library process](https://github.com/ballerina-platform/ballerina-library/blob/main/docs/library-development-process.md#specification) when making enhancements to the current library specification.

This effort aims to establish a standard process for the entire Ballerina Platform, including the Ballerina language, build tooling, libraries, connectors, and integration tools. This will help us track the platform's enhancements in a central location and even create a development roadmap. External contributors can also participate by following the established process.

## Ballerina Enhancement Proposals(BEP) 

> Inspired by [Kubernetes Enhancement Proposals (KEPs)](https://github.com/kubernetes/enhancements/blob/master/keps/README.md)

BEPs is a single-file document(.md format) that describes the enhancements the user needs in the Ballerina platform.

### What type of work should go to BEP

* Any type of enhancement that needs to be updated in the current specification. Any Ballerina user or developer who is facing an enhancement to the current support should follow the BEP process.
* Any significant refactoring or architectural change, regardless of whether it has zero impact or a substantial impact
* Enhancements that have impacts on multiple areas.

### BEP Template

> Inspired by [JEP format](https://openjdk.org/jeps/2)

The template can be found in [here](0000_bep_template.md)

### BEP Metadata

### BEP Workflow

* `Submitted` - The BEP has been proposed and is currently being defined. This represents the initial phase of its development and discussion.
* `Accepted` - The approvers have approved this BEP for implementation.
* `Implemented` - The BEP has been implemented and is no longer being actively changed.
* `Deferred` - The BEP is proposed but not currently in progress.
* `Rejected`—The approvers and authors have determined that this BEP will not proceed.

### Where should BEPs be checked

BEPs are stored in the [`ballerina-spec`](https://github.com/ballerina-platform/ballerina-spec) repository within the /beps directory. Each BEP is placed in its specific subdirectory, which is categorized based on the presence of a specification. For example, the BEP for the Ballerina log library is placed in the `beps/lib-log` directory. Prefix the BEP file with the GitHub issue number and a short, descriptive title. For example, [`1322_contextual_logging.md](../lib-log/1322_contextual_logging.md).

### GitHub Issue for BEP discussion

A GitHub issue should be created in the ballerina-platform/ballerina-spec repo. This issue should be used to discuss the proposal and get feedback from the community. It should be linked to the BEP file, and the issue number should be the prefix of the BEP file.
