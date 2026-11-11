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
          <strong>Hosting.</strong> Netlify hosts this site. Netlify
          processes access data such as your IP address, see
          the <a href="https://www.netlify.com/privacy/">Netlify
          privacy statement</a>.
        </p>
        <p>
          <strong>Analytics.</strong> <a href="https://www.goatcounter.com/help/privacy">GoatCounter</a> counts
          which pages are visited, without cookies or tracking IDs. It does
          not permanently store IP addresses or full user agents. The collection
          endpoint on this site forwards technical visit data to GoatCounter.
        </p>
      </main>
    </Layout>
  );
}
