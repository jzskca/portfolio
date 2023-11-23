import { gql } from "@apollo/client";
import { ASTKindToNode, ASTNode, DocumentNode, visit, Visitor } from "graphql/language";

import { hasFeatureX } from "utilities/helpers/hasFeature";

const directiveOperations: Record<string, (currentNode: ASTNode) => ASTNode | null> = {
    ifHasFeatureX: (currentNode) => (hasFeatureX() ? currentNode : null),
    noop: (_currentNode) => undefined,
    remove: (_currentNode) => null,
};

// `gql` with custom (client-side) directive processing
const customDirectivesGQL = (literals: string | readonly string[], ...args: any[]): DocumentNode => {
    const variablesToRemove: string[] = [];
    const visitor: Visitor<ASTKindToNode, ASTNode> = {
        enter(node) {
            // Remove arguments that rely on removed variables
            if (node.kind === "Argument" || node.kind === "ObjectField") {
                if (node.value.kind === "Variable" && variablesToRemove.includes(node.value.name.value)) return null;
            }

            // Remove custom directives from the document after processing
            if (node.kind === "Directive") {
                return node.name.value in directiveOperations ? null : undefined;
            }

            if (!("directives" in node && node.directives)) return undefined;

            // Process custom directives one at a time and return the final result
            return node.directives.reduce((result, directive) => {
                // If another directive deleted this node, no further processing is possible
                if (result === null) return result;

                // If this isn't a custom directive, continue to the next
                if (!(directive.name.value in directiveOperations)) return result;

                // Process directive
                const directiveResult = directiveOperations[directive.name.value](result);

                // If the directive removed a variable definition, flag variable usages to be removed as well
                if (node.kind === "VariableDefinition" && directiveResult === null) {
                    variablesToRemove.push(node.variable.name.value);
                }

                return directiveResult;
            }, undefined);
        },
    };

    // To debug, import `print` from `graphql/language` and pass in the result of `visit`
    const doc: DocumentNode = gql(literals, ...args);
    return visit(doc, visitor);
};

export default customDirectivesGQL;
