import Layout from '@theme/Layout';

export default function Privacy() {
  return (
    <Layout title="Privacy">
      <main className="container margin-vert--lg">
        <h1>Privacy</h1>
        <p>
          Responsible for this site: Robert Schäfer, contact details in
          the <a href="https://roschaefer.de/en/imprint/">imprint</a>.
        </p>
        <p>
          <strong>Hosting.</strong> GitHub Pages hosts this site. GitHub
          processes access data such as your IP address, see
          the <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">GitHub
          privacy statement</a>.
        </p>
        <p>
          <strong>Analytics.</strong> <a href="https://www.goatcounter.com/help/privacy">GoatCounter</a> counts
          which pages are visited, without cookies or tracking IDs. It does
          not keep IP addresses or full user agents.
        </p>
      </main>
    </Layout>
  );
}
