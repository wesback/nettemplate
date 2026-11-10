import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";

import Page from "./page";

test("Given_the_home_page_When_rendered_Then_it_has_a_main_landmark", () => {
  render(<Page />);
  expect(screen.getByRole("main")).toBeDefined();
});
