import { print } from "graphql/language";

import customDirectivesGQL from "graphql/customDirectivesGQL";
import { hasFeatureX } from "utilities/helpers/hasFeature";
import { dedent } from "utilities/testing";

jest.mock("utilities/helpers/isSite", () => ({
    ...jest.requireActual("utilities/helpers/isSite"),
    hasFeatureX: jest.fn(),
}));

describe("customDirectivesGQL()", () => {
    it("leaves documents without custom directives intact", () => {
        const result = customDirectivesGQL/* GraphQL */ `
            query foo($var1: Boolean @directive1, $var2: String) {
                foo(arg1: $var1, arg2: $var2) {
                    bar {
                        alpha
                        beta
                    }
                    baz @directive2(if: true) {
                        gamma
                        delta
                    }
                }
            }
        `;
        const expected = dedent(`
            query foo($var1: Boolean @directive1, $var2: String) {
              foo(arg1: $var1, arg2: $var2) {
                bar {
                  alpha
                  beta
                }
                baz @directive2(if: true) {
                  gamma
                  delta
                }
              }
            }
        `);
        expect(print(result)).toEqual(expected);
    });

    it("removes custom directives from output document", () => {
        const result = customDirectivesGQL/* GraphQL */ `
            query foo($var1: Boolean @noop) {
                foo(arg1: $var1) {
                    bar @noop {
                        alpha @noop
                    }
                }
            }
        `;
        const expected = dedent(`
            query foo($var1: Boolean) {
              foo(arg1: $var1) {
                bar {
                  alpha
                }
              }
            }
        `);
        expect(print(result)).toEqual(expected);
    });

    it("halts further directive processing when previous directive removes node", () => {
        const result = customDirectivesGQL/* GraphQL */ `
            query foo($var1: Boolean @remove @noop) {
                foo(arg1: $var1) {
                    bar @remove @noop {
                        alpha @remove @noop
                    }
                    baz
                }
            }
        `;
        const expected = dedent(`
            query foo {
              foo {
                baz
              }
            }
        `);
        expect(print(result)).toEqual(expected);
    });

    describe("with `@ifHasFeatureX`", () => {
        const doc = /* GraphQL */ `
            query foo($var1: Boolean @ifHasFeatureX, $var2: String) {
                foo(arg1: $var1, arg2: $var2) {
                    bar @ifHasFeatureX {
                        alpha
                        beta
                    }
                    baz {
                        gamma @ifHasFeatureX
                        delta
                    }
                }
            }
        `;

        it("when enabled", () => {
            hasFeatureX.mockReturnValue(true);
            const result = customDirectivesGQL(doc);
            const expected = dedent(`
                query foo($var1: Boolean, $var2: String) {
                  foo(arg1: $var1, arg2: $var2) {
                    bar {
                      alpha
                      beta
                    }
                    baz {
                      gamma
                      delta
                    }
                  }
                }
            `);
            expect(print(result)).toEqual(expected);
        });

        it("when disabled", () => {
            hasFeatureX.mockReturnValue(false);
            const result = customDirectivesGQL(doc);
            const expected = dedent(`
                query foo($var2: String) {
                  foo(arg2: $var2) {
                    baz {
                      delta
                    }
                  }
                }
            `);
            expect(print(result)).toEqual(expected);
        });
    });
});
